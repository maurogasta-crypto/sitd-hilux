import '../../core/db/base.dart';
import 'carga.dart';

/// Las cargas de combustible en la base, y el ajuste del tanque.
class RegistroDeCargas {
  final Base base;

  /// Capacidad del tanque, en litros. La Hilux 3.0 doble cabina trae 80; se
  /// puede cambiar desde la pantalla porque el dato del fabricante y lo que
  /// entra de verdad no siempre coinciden.
  static const double litrosDelTanquePorDefecto = 80;
  static const String _claveTanque = 'litros_del_tanque';

  RegistroDeCargas(this.base);

  /// Guarda una carga y devuelve su identificador.
  ///
  /// Lanza si la carga tiene un problema: lo que no pasa la validación no
  /// llega a la base. Un litro negativo guardado arruina el promedio de todo
  /// un año y no hay forma de saber cuál fue.
  int guardar(Carga c) {
    final problema = c.problema;
    if (problema != null) throw ArgumentError(problema);
    base.db.execute(
      'INSERT INTO cargas (t, litros, costo, moneda, odo_tablero, '
      'tanque_lleno, estacion, notas) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        c.t,
        c.litros,
        c.costo,
        c.moneda,
        c.odoTablero,
        c.tanqueLleno ? 1 : 0,
        c.estacion,
        c.notas,
      ],
    );
    return base.db.lastInsertRowId;
  }

  void borrar(int id) =>
      base.db.execute('DELETE FROM cargas WHERE id = ?', [id]);

  /// Todas las cargas, de la más vieja a la más nueva.
  ///
  /// En ese orden y no al revés a propósito: el consumo se calcula recorriendo
  /// la historia hacia adelante, y darlo vuelta en la pantalla es una línea.
  List<Carga> todas() => base.db
      .select('SELECT * FROM cargas ORDER BY t')
      .map(
        (f) => Carga(
          id: f['id'] as int,
          t: f['t'] as int,
          litros: (f['litros'] as num).toDouble(),
          costo: (f['costo'] as num?)?.toDouble(),
          moneda: f['moneda'] as String,
          odoTablero: (f['odo_tablero'] as num).toDouble(),
          tanqueLleno: (f['tanque_lleno'] as int) != 0,
          estacion: f['estacion'] as String?,
          notas: f['notas'] as String?,
        ),
      )
      .toList();

  /// La última lectura del odómetro que se tecleó, para proponerla como piso
  /// en la próxima carga. Un odómetro no retrocede, y proponerlo evita el
  /// error más común: teclear los kilómetros del viaje en vez del total.
  double? get ultimoOdometro {
    final f = base.db.select(
      'SELECT odo_tablero FROM cargas ORDER BY t DESC LIMIT 1',
    );
    return f.isEmpty ? null : (f.first['odo_tablero'] as num).toDouble();
  }

  double get litrosDelTanque {
    final v = base.leerAjuste(_claveTanque);
    return double.tryParse(v ?? '') ?? litrosDelTanquePorDefecto;
  }

  set litrosDelTanque(double litros) =>
      base.escribirAjuste(_claveTanque, '$litros');
}
