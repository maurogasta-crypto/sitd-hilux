/// Volver a meter un respaldo en el teléfono.
///
/// ## Por qué faltaba, y por qué entra ahora
///
/// Desde `sitd-7` se puede sacar una copia de la base y no devolverla: el
/// respaldo guardaba la historia pero no la traía de vuelta. Mientras cada
/// tanda obligaba a desinstalar —y desinstalar borra el SQLite— eso era lo
/// único que separaba «tengo el archivo» de «tengo los viajes».
///
/// Con la clave de firma propia (`sitd-21`) una actualización ya no borra
/// nada, así que esto dejó de ser una urgencia. Sigue haciendo falta para tres
/// cosas que no se van: **la última desinstalación**, la que pasa de la firma
/// de depuración a la propia; **el teléfono que se rompe**; y **mudar la
/// historia al Note 9** cuando aparezca.
///
/// ## Las cuatro cosas que tiene que hacer bien
///
/// 1. **Mirar la versión del esquema ANTES de tocar nada.** Una base más nueva
///    que la aplicación no se importa: las tablas que todavía no existen acá
///    se perderían en silencio, que es la peor forma de fallar. Una más vieja
///    sí, migrando una COPIA — nunca el archivo original de Mauro.
/// 2. **Decir exactamente qué se pierde**, con los números de los dos lados.
///    «¿Estás seguro?» no es una pregunta: no dice qué pasa si uno dice que sí.
/// 3. **No dejar la base a medias.** Todo el reemplazo va en UNA transacción:
///    si algo falla en el medio, se deshace entero y el teléfono queda como
///    estaba. Es la diferencia entre un error y una pérdida.
/// 4. **No traerse la credencial del archivo.** Un `.db` de antes de `sitd-21`
///    la lleva adentro, y podría ser una que ya se rotó. La que vale es la que
///    el teléfono tiene AHORA: se guarda antes, se importa lo demás, y se
///    vuelve a escribir.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../core/db/base.dart';
import '../../core/db/esquema.dart';
import '../nube/credencial.dart';
import '../nube/sesion.dart';
import 'saneado.dart';

/// Qué tablas viajan, y por qué `ajustes` no.
///
/// `ajustes` es la configuración de ESTE teléfono —el modo de GPS que le
/// anduvo, la credencial de la nube, los litros del tanque—, no la historia.
/// Traerla de otro aparato pisaría lo que acá funciona con lo que allá
/// funcionaba. La historia se muda; las mañas del teléfono, no.
///
/// **Si mañana entra una tabla nueva, entra acá en la misma tanda.** Hay una
/// prueba que compara esta lista contra las tablas del esquema y falla si
/// alguien agrega una y se olvida — es la misma red que las colecciones y sus
/// reglas.
const List<String> tablasQueSeImportan = [
  // `viajes` va PRIMERO: las otras tres lo referencian, y el borrado en
  // cascada las limpia de arriba abajo. Al insertar, el orden es el mismo.
  'viajes',
  'puntos',
  'vibraciones',
  'subidas',
  'cargas',
  'eventos',
];

/// Lo que no se muda, con el motivo al lado para que nadie lo agregue por
/// prolijidad.
const List<String> tablasQueNoSeImportan = ['ajustes'];

/// Cuánto hay de cada cosa. Es lo que se le muestra a Mauro de los dos lados
/// antes de preguntarle nada.
class Inventario {
  final int viajes;
  final int puntos;
  final int cargas;
  final int vibraciones;

  const Inventario({
    this.viajes = 0,
    this.puntos = 0,
    this.cargas = 0,
    this.vibraciones = 0,
  });

  bool get vacio => viajes == 0 && puntos == 0 && cargas == 0;

  /// En los términos de quien mira la pantalla, no en los de la base.
  String get resumen => vacio
      ? 'sin viajes'
      : '$viajes ${viajes == 1 ? 'viaje' : 'viajes'}, '
            '$puntos ${puntos == 1 ? 'punto' : 'puntos'}, '
            '$cargas ${cargas == 1 ? 'carga' : 'cargas'}';
}

Inventario _inventariar(Database db) {
  int cuantos(String tabla) {
    try {
      return db.select('SELECT COUNT(*) AS n FROM $tabla').first['n'] as int;
    } on SqliteException {
      // Una base vieja puede no tener la tabla todavía. Cero es la verdad.
      return 0;
    }
  }

  return Inventario(
    viajes: cuantos('viajes'),
    puntos: cuantos('puntos'),
    cargas: cuantos('cargas'),
    vibraciones: cuantos('vibraciones'),
  );
}

/// Qué se sabe de un archivo antes de tocarlo.
class RevisionRespaldo {
  /// `null` si se puede importar; si no, por qué no, en una frase.
  final String? problema;

  /// Lo que trae el archivo, cuando se pudo leer.
  final Inventario? candidato;

  /// Lo que hay ahora en el teléfono.
  final Inventario actual;

  /// La versión del esquema del archivo.
  final int? version;

  const RevisionRespaldo({
    required this.actual,
    this.problema,
    this.candidato,
    this.version,
  });

  bool get sePuede => problema == null;
}

/// Mira el archivo SIN tocarlo y sin tocar la base viva.
RevisionRespaldo revisarRespaldo({required Base viva, required String ruta}) {
  final actual = _inventariar(viva.db);
  if (!File(ruta).existsSync()) {
    return RevisionRespaldo(actual: actual, problema: 'Ese archivo no está.');
  }

  Database? db;
  try {
    db = sqlite3.open(ruta, mode: OpenMode.readOnly);
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > versionEsquema) {
      return RevisionRespaldo(
        actual: actual,
        version: version,
        problema:
            'Ese respaldo es de una versión MÁS NUEVA de la aplicación '
            '(esquema $version contra $versionEsquema). No se importa: lo que '
            'la aplicación todavía no sabe guardar se perdería sin aviso. '
            'Actualizá primero.',
      );
    }
    final tablas = db
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'viajes'",
        )
        .isNotEmpty;
    if (!tablas) {
      return RevisionRespaldo(
        actual: actual,
        version: version,
        problema:
            'Ese archivo es una base de datos, pero no de esta '
            'aplicación: no tiene la tabla de viajes.',
      );
    }
    return RevisionRespaldo(
      actual: actual,
      candidato: _inventariar(db),
      version: version,
    );
  } on SqliteException catch (e) {
    return RevisionRespaldo(
      actual: actual,
      problema:
          'Ese archivo no se puede abrir como base de datos (${e.message}).',
    );
  } finally {
    db?.dispose();
  }
}

/// Las columnas que tienen las DOS bases, en el orden de la de acá.
///
/// Una que esté acá y no en el respaldo —porque el respaldo es más viejo— se
/// deja afuera y toma su valor por defecto, que es exactamente lo que hay que
/// hacer: el dato no existía cuando se guardó.
List<String> _columnasComunes(Database db, String tabla) {
  List<String> de(String esquema) => db
      .select('PRAGMA $esquema.table_info($tabla)')
      .map((f) => f['name'] as String)
      .toList();
  final viejas = de('viejo').toSet();
  return de('main').where(viejas.contains).toList();
}

/// Reemplaza la historia del teléfono por la del respaldo.
///
/// Devuelve `null` si salió bien, o el motivo si no. **Si falla, la base queda
/// exactamente como estaba**: todo va en una transacción.
///
/// [carpetaDeTrabajo] es donde se hace la copia que se migra. Tiene que ser de
/// la aplicación: el archivo de Mauro no se toca nunca.
String? importarRespaldo({
  required Base viva,
  required String ruta,
  required String carpetaDeTrabajo,
}) {
  final revision = revisarRespaldo(viva: viva, ruta: ruta);
  if (!revision.sePuede) return revision.problema;

  final copia = File('$carpetaDeTrabajo/importando.db');
  try {
    if (copia.existsSync()) copia.deleteSync();
    File(ruta).copySync(copia.path);

    // La copia se migra hasta la versión de esta aplicación. El original no se
    // abre para escribir en ningún momento.
    final migrada = Base.abrir(copia.path);
    migrada.cerrar();

    // Y se le saca la credencial, que puede venir de antes de `sitd-21` y ser
    // una que ya se rotó. Reusa el saneado del respaldo: una sola definición
    // de qué es lo que no puede viajar.
    sanearCopia(copia.path);

    // Lo que el teléfono tiene AHORA y tiene que seguir teniendo después.
    final credencial = viva.leerAjuste(claveDeLaCredencial);
    final sesion = viva.leerAjuste(claveDeLaSesion);

    final db = viva.db;
    db.execute(
      "ATTACH DATABASE '${copia.path.replaceAll("'", "''")}' AS viejo",
    );
    try {
      db.execute('BEGIN IMMEDIATE');
      try {
        // Borrar `viajes` arrastra en cascada a puntos, vibraciones y subidas;
        // se borran igual de a una para no depender de que las claves foráneas
        // estén encendidas en esta conexión.
        for (final tabla in tablasQueSeImportan.reversed) {
          db.execute('DELETE FROM $tabla');
        }
        for (final tabla in tablasQueSeImportan) {
          /* ── LAS COLUMNAS SE NOMBRAN, NO SE USA `SELECT *` ────────────────
             `INSERT INTO t SELECT * FROM viejo.t` copia POR POSICIÓN, así que
             depende de que las dos bases tengan las columnas en el mismo
             orden. Hoy lo están —las dos se arman corriendo las migraciones
             desde cero— pero eso es una coincidencia del camino, no una
             garantía: el día que alguien cree una tabla con las columnas ya
             puestas en vez de agregarlas con ALTER, el orden cambia y esto
             metería la precisión en el campo de los cortes SIN ERROR. Se
             nombran, y se usan sólo las que están en las dos. */
          final columnas = _columnasComunes(db, tabla);
          if (columnas.isEmpty) continue;
          final lista = columnas.join(', ');
          db.execute(
            'INSERT INTO $tabla ($lista) SELECT $lista FROM viejo.$tabla',
          );
        }
        db.execute('COMMIT');
      } on SqliteException {
        db.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      db.execute('DETACH DATABASE viejo');
    }

    // La credencial vuelve DESPUÉS y fuera de la transacción: `ajustes` no se
    // tocó, así que esto sólo repone lo que el saneado podría haber alterado
    // si algún día la lista de tablas cambiara.
    if (credencial != null && credencial.isNotEmpty) {
      viva.escribirAjuste(claveDeLaCredencial, credencial);
    }
    if (sesion != null && sesion.isNotEmpty) {
      viva.escribirAjuste(claveDeLaSesion, sesion);
    }
    return null;
  } on SqliteException catch (e) {
    return 'No se pudo importar: ${e.message}. La base quedó como estaba.';
  } on FileSystemException catch (e) {
    return 'No se pudo leer el archivo: ${e.message}';
  } finally {
    if (copia.existsSync()) {
      try {
        copia.deleteSync();
      } on FileSystemException {
        // Que no se pueda borrar el temporal no invalida la importación.
      }
    }
  }
}
