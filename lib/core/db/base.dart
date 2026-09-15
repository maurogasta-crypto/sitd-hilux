import 'package:sqlite3/sqlite3.dart';

import 'esquema.dart';

/// Apertura y migración de la base local.
///
/// **Por qué WAL y no un único hilo escritor en Dart.** La aplicación tiene
/// tres productores concurrentes —el servicio de GPS, el trabajador de
/// análisis y la interfaz— y cada uno vive en su propio isolate. En modo WAL,
/// SQLite admite un escritor y varios lectores a la vez sin bloquearlos, y
/// `busy_timeout` hace que un segundo escritor espere su turno en vez de
/// devolver `SQLITE_BUSY`. Es la misma garantía que daría un hilo escritor
/// hecho a mano, pero la da la base y no un invariante que hay que recordar.
///
/// Cada isolate abre su propia conexión al mismo archivo. Las conexiones NO se
/// comparten entre isolates: un puntero nativo no sobrevive el cruce.
class Base {
  final Database db;

  Base._(this.db);

  /// Abre la base en [ruta] y la deja en la última versión del esquema.
  ///
  /// Pasar `:memory:` como ruta sirve para el banco de pruebas.
  factory Base.abrir(String ruta) {
    final db = sqlite3.open(ruta);

    // En memoria no hay WAL posible ni hace falta.
    if (ruta != ':memory:') {
      db.execute('PRAGMA journal_mode = WAL');
    }
    db.execute('PRAGMA busy_timeout = 5000');
    db.execute('PRAGMA foreign_keys = ON');
    // NORMAL con WAL es seguro ante caída de la aplicación; sólo se pierde la
    // última transacción si se corta la energía del teléfono entero. A cambio
    // evita un fsync por escritura, que a 1 Hz de GPS se nota.
    db.execute('PRAGMA synchronous = NORMAL');

    _migrar(db);
    return Base._(db);
  }

  static void _migrar(Database db) {
    final actual = db.select('PRAGMA user_version').first.values.first as int;

    if (actual > versionEsquema) {
      throw StateError(
        'La base está en la versión $actual y esta compilación entiende hasta '
        'la $versionEsquema. Es una instalación más nueva: no se toca.',
      );
    }
    if (actual == versionEsquema) return;

    for (var v = actual; v < versionEsquema; v++) {
      db.execute('BEGIN');
      try {
        for (final sql in migraciones[v]) {
          db.execute(sql);
        }
        db.execute('PRAGMA user_version = ${v + 1}');
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  int get version => db.select('PRAGMA user_version').first.values.first as int;

  /// Las tablas que existen, ordenadas. Sirve para verificar una migración.
  List<String> get tablas => db
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .map((f) => f['name'] as String)
      .toList();

  String? leerAjuste(String clave) {
    final f = db.select('SELECT valor FROM ajustes WHERE clave = ?', [clave]);
    return f.isEmpty ? null : f.first['valor'] as String;
  }

  void escribirAjuste(String clave, String valor) {
    db.execute(
      'INSERT INTO ajustes (clave, valor) VALUES (?, ?) '
      'ON CONFLICT (clave) DO UPDATE SET valor = excluded.valor',
      [clave, valor],
    );
  }

  void cerrar() => db.close();
}
