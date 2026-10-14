import '../../core/db/base.dart';
import 'regimen.dart';

/// Una ventana de micrófono ya resumida: lo que queda en la base.
class VentanaAudio {
  final int t;
  final double kmh;
  final double? rpm;
  final double prominencia;
  final double nivel;
  final int hz;
  final List<double> bandas;

  const VentanaAudio({
    required this.t,
    required this.kmh,
    required this.rpm,
    required this.prominencia,
    required this.nivel,
    required this.hz,
    required this.bandas,
  });

  factory VentanaAudio.de(
    LecturaMotor l, {
    required int t,
    required double kmh,
  }) => VentanaAudio(
    t: t,
    kmh: kmh,
    rpm: l.rpm,
    prominencia: l.prominenciaDb,
    nivel: l.nivelDb,
    hz: hzAudio,
    bandas: l.bandas,
  );

  /// Para el reporte: claves cortas, porque un viaje largo junta cientos.
  Map<String, dynamic> aMapa() => {
    't': t,
    'kmh': double.parse(kmh.toStringAsFixed(1)),
    'rpm': rpm?.round(),
    'prom': double.parse(prominencia.toStringAsFixed(1)),
    'db': double.parse(nivel.toStringAsFixed(1)),
    'bandas': [
      for (final b in bandas) double.parse(b.toStringAsExponential(3)),
    ],
  };
}

/// Las ventanas del micrófono en la base (`sitd-37`).
class RegistroDeAudio {
  final Base base;

  RegistroDeAudio(this.base);

  void guardar(int viaje, VentanaAudio v) {
    base.db.execute(
      'INSERT INTO audio (viaje, t, kmh, rpm, prominencia, nivel, hz, bandas) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        viaje,
        v.t,
        v.kmh,
        v.rpm,
        v.prominencia,
        v.nivel,
        v.hz,
        v.bandas.join(','),
      ],
    );
  }

  List<VentanaAudio> deViaje(int viaje) => base.db
      .select('SELECT * FROM audio WHERE viaje = ? ORDER BY t', [viaje])
      .map(
        (f) => VentanaAudio(
          t: f['t'] as int,
          kmh: (f['kmh'] as num).toDouble(),
          rpm: (f['rpm'] as num?)?.toDouble(),
          prominencia: (f['prominencia'] as num).toDouble(),
          nivel: (f['nivel'] as num).toDouble(),
          hz: f['hz'] as int,
          bandas: (f['bandas'] as String)
              .split(',')
              .where((x) => x.isNotEmpty)
              .map(double.parse)
              .toList(),
        ),
      )
      .toList();

  int cuantas() =>
      base.db.select('SELECT COUNT(*) AS n FROM audio').first['n'] as int;
}
