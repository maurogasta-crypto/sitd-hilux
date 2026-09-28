import '../../core/db/base.dart';
import 'analisis.dart';
import 'ventana.dart';

/// Los vectores de vibración en la base.
class RegistroDeVibracion {
  final Base base;

  RegistroDeVibracion(this.base);

  void guardar(int viaje, VentanaVibracion v) {
    base.db.execute(
      'INSERT INTO vibraciones (viaje, t, cubeta, hz, muestras, rms, pico, '
      'bandas) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        viaje,
        v.t,
        v.cubeta,
        v.hz,
        v.muestras,
        v.rms,
        v.pico,
        v.bandas.join(','),
      ],
    );
  }

  /// Todas las ventanas agrupadas por viaje, que es como las pide el análisis:
  /// la línea base se arma dejando afuera viajes enteros, no ventanas sueltas.
  Map<int, List<VentanaVibracion>> porViaje() {
    final salida = <int, List<VentanaVibracion>>{};
    for (final f in base.db.select('SELECT * FROM vibraciones ORDER BY t')) {
      (salida[f['viaje'] as int] ??= []).add(_aVentana(f));
    }
    return salida;
  }

  List<VentanaVibracion> deViaje(int viaje) => base.db
      .select('SELECT * FROM vibraciones WHERE viaje = ? ORDER BY t', [viaje])
      .map(_aVentana)
      .toList();

  /// Cuántas ventanas hay por cubeta, para poder decir cuánto falta antes de
  /// que la línea base signifique algo.
  ///
  /// **Sólo las que se pueden comparar** (`sitd-35`): una ventana medida a
  /// 12,6 Hz no le enseña nada a la línea base, y contarla haría que una
  /// cubeta pareciera lista sin estarlo. Las otras las cuenta
  /// [ventanasABajaFrecuencia].
  Map<int, int> ventanasPorCubeta() {
    final salida = <int, int>{};
    for (final f in base.db.select(
      'SELECT cubeta, COUNT(*) AS n FROM vibraciones WHERE hz >= ? '
      'GROUP BY cubeta',
      [hzMinimoParaComparar],
    )) {
      salida[f['cubeta'] as int] = f['n'] as int;
    }
    return salida;
  }

  /// Las ventanas guardadas que NO se comparan porque el sistema entregó el
  /// acelerómetro por debajo de [hzMinimoParaComparar]. Se muestran aparte: si
  /// crecen, el teléfono está recortando el sensor —pantalla apagada, ahorro
  /// de batería— y eso hay que saberlo, no descubrirlo.
  int ventanasABajaFrecuencia() =>
      base.db.select('SELECT COUNT(*) AS n FROM vibraciones WHERE hz < ?', [
            hzMinimoParaComparar,
          ]).first['n']
          as int;

  /// Los viajes que tienen vibración, del más nuevo al más viejo. Es el orden
  /// que pide la histéresis: los tres últimos, no tres cualesquiera.
  List<int> ultimosViajes([int cuantos = 20]) => base.db
      .select(
        'SELECT viaje, MAX(t) AS ultimo FROM vibraciones GROUP BY viaje '
        'ORDER BY ultimo DESC LIMIT ?',
        [cuantos],
      )
      .map((f) => f['viaje'] as int)
      .toList();

  static VentanaVibracion _aVentana(dynamic f) => VentanaVibracion(
    t: f['t'] as int,
    cubeta: f['cubeta'] as int,
    hz: (f['hz'] as num).toDouble(),
    muestras: f['muestras'] as int,
    rms: (f['rms'] as num).toDouble(),
    pico: (f['pico'] as num).toDouble(),
    bandas: [
      for (final x in (f['bandas'] as String).split(','))
        double.tryParse(x) ?? 0,
    ],
  );
}
