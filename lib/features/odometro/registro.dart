import 'package:sqlite3/sqlite3.dart';

import '../../core/db/base.dart';
import 'integrador.dart';
import 'muestra.dart';

/// Un viaje, tal como quedó guardado.
///
/// `metros` y `metrosHaversine` son un **derivado guardado**, que es la
/// excepción a la regla del proyecto, y conviene que se sepa por qué: son la
/// única forma de listar cien viajes sin releer un millón de puntos. La
/// autoridad sigue siendo `puntos`: [RegistroDeViajes.recalcular] los vuelve a
/// sacar de ahí y pisa estos dos, y si mañana mejora el filtro se recalculan
/// todos los viajes viejos. Un derivado se vuelve a calcular; una muestra
/// perdida, no.
class Viaje {
  final int id;
  final int inicio;
  final int? fin;
  final double metros;
  final double metrosHaversine;
  final int cortes;
  final double? odoTableroIni;
  final double? odoTableroFin;
  final String? notas;

  const Viaje({
    required this.id,
    required this.inicio,
    required this.metros,
    required this.metrosHaversine,
    required this.cortes,
    this.fin,
    this.odoTableroIni,
    this.odoTableroFin,
    this.notas,
  });

  bool get enMarcha => fin == null;
  double get kilometros => metros / 1000.0;

  /// Duración en milisegundos contra [ahora] si el viaje sigue abierto.
  int duracionMs(int ahora) => (fin ?? ahora) - inicio;
}

/// Todo lo que la odometría escribe y lee de la base.
///
/// Está separado del servicio a propósito: el servicio decide *cuándo* se
/// guarda algo y esto sabe *cómo*. Así el banco de pruebas puede ejercitar la
/// base entera —con `:memory:`— sin GPS, sin permisos y sin teléfono.
class RegistroDeViajes {
  final Base base;

  RegistroDeViajes(this.base);

  /// Se prepara una sola vez: a 1 Hz esto se ejecuta una vez por segundo
  /// durante horas, y volver a compilar el SQL en cada punto es trabajo
  /// regalado.
  late final PreparedStatement _insertarPunto = base.db.prepare(
    'INSERT INTO puntos (viaje, t, lat, lon, alt, velocidad, precision_m, '
    'precision_vel) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );

  /// Abre un viaje y devuelve su identificador.
  int abrir({required int inicio, double? odoTablero}) {
    base.db.execute(
      'INSERT INTO viajes (inicio, odo_tablero_ini) VALUES (?, ?)',
      [inicio, odoTablero],
    );
    return base.db.lastInsertRowId;
  }

  /// Guarda una muestra cruda. **Se guardan todas las aceptadas, uno por uno.**
  ///
  /// Se evaluó juntarlas de a diez para ahorrar escrituras y no vale la pena:
  /// en modo WAL con `synchronous = NORMAL` un INSERT por segundo no se nota,
  /// y el precio de juntarlas es perder hasta diez segundos de recorrido si el
  /// sistema mata la aplicación — que es exactamente lo que hace MIUI.
  void guardarPunto(int viaje, Muestra m) {
    _insertarPunto.execute([
      viaje,
      m.t,
      m.lat,
      m.lon,
      m.alt,
      m.velocidad,
      m.precision,
      m.precisionVel,
    ]);
  }

  /// Vuelca el estado de la odometría sobre la fila del viaje.
  void actualizar(int viaje, ResultadoOdometria r) {
    base.db.execute(
      'UPDATE viajes SET metros = ?, metros_haversine = ?, cortes = ? '
      'WHERE id = ?',
      [r.metros, r.metrosHaversine, r.cortes, viaje],
    );
  }

  /// Cierra el viaje. Con [odometria] además deja escrito el total.
  void cerrar(
    int viaje, {
    required int fin,
    ResultadoOdometria? odometria,
    double? odoTablero,
  }) {
    if (odometria != null) actualizar(viaje, odometria);
    base.db.execute(
      'UPDATE viajes SET fin = ?, odo_tablero_fin = COALESCE(?, odo_tablero_fin) '
      'WHERE id = ?',
      [fin, odoTablero, viaje],
    );
  }

  /// El viaje que quedó sin cerrar, si hay alguno.
  ///
  /// **Esto es la recuperación después de una muerte súbita.** Si el sistema
  /// mató la aplicación en medio de un viaje —y MIUI lo hace—, al volver a
  /// abrir queda una fila con `fin` en nulo y sus puntos guardados. No se
  /// pierde nada: se retoma ese viaje y se sigue.
  Viaje? get abierto {
    final f = base.db.select(
      'SELECT * FROM viajes WHERE fin IS NULL ORDER BY inicio DESC LIMIT 1',
    );
    return f.isEmpty ? null : _aViaje(f.first);
  }

  Viaje? porId(int id) {
    final f = base.db.select('SELECT * FROM viajes WHERE id = ?', [id]);
    return f.isEmpty ? null : _aViaje(f.first);
  }

  List<Viaje> ultimos([int cuantos = 20]) => base.db
      .select('SELECT * FROM viajes ORDER BY inicio DESC LIMIT ?', [cuantos])
      .map(_aViaje)
      .toList();

  /// Las muestras crudas de un viaje, en orden.
  List<Muestra> puntosDe(int viaje) => base.db
      .select('SELECT * FROM puntos WHERE viaje = ? ORDER BY t', [viaje])
      .map(
        (f) => Muestra(
          t: f['t'] as int,
          lat: f['lat'] as double,
          lon: f['lon'] as double,
          alt: f['alt'] as double?,
          velocidad: f['velocidad'] as double,
          precision: f['precision_m'] as double,
          precisionVel: f['precision_vel'] as double?,
        ),
      )
      .toList();

  /// Recalcula un viaje desde sus muestras crudas y pisa lo guardado.
  ///
  /// Es la razón por la que las muestras se guardan enteras: el día que cambie
  /// un umbral de [CriteriosGps] o mejore el filtro, los viajes viejos se
  /// vuelven a calcular sin haber perdido nada.
  ResultadoOdometria recalcular(
    int viaje, {
    CriteriosGps criterios = const CriteriosGps(),
  }) {
    final r = integrar(puntosDe(viaje), criterios: criterios);
    actualizar(viaje, r);
    return r;
  }

  void cerrarRecursos() => _insertarPunto.close();

  static Viaje _aViaje(Row f) => Viaje(
    id: f['id'] as int,
    inicio: f['inicio'] as int,
    fin: f['fin'] as int?,
    metros: (f['metros'] as num).toDouble(),
    metrosHaversine: (f['metros_haversine'] as num).toDouble(),
    cortes: f['cortes'] as int,
    odoTableroIni: (f['odo_tablero_ini'] as num?)?.toDouble(),
    odoTableroFin: (f['odo_tablero_fin'] as num?)?.toDouble(),
    notas: f['notas'] as String?,
  );
}
