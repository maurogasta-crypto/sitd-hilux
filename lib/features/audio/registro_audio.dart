import '../../core/db/base.dart';
import 'regimen.dart';

/// Una ventana de micrófono ya resumida: lo que queda en la base.
class VentanaAudio {
  final int t;
  final double kmh;
  final double? rpm;
  final int? marcha;
  final double prominencia;
  final double nivel;
  final int hz;
  final List<double> bandas;
  final List<double?> porMarcha;
  final List<double> picos;

  const VentanaAudio({
    required this.t,
    required this.kmh,
    required this.rpm,
    this.marcha,
    required this.prominencia,
    required this.nivel,
    required this.hz,
    required this.bandas,
    this.porMarcha = const [],
    this.picos = const [],
  });

  factory VentanaAudio.de(
    LecturaMotor l, {
    required int t,
    required double kmh,
  }) => VentanaAudio(
    t: t,
    kmh: kmh,
    rpm: l.rpm,
    marcha: l.marcha,
    prominencia: l.prominenciaDb,
    nivel: l.nivelDb,
    hz: hzAudio,
    bandas: l.bandas,
    porMarcha: l.porMarcha,
    picos: l.picos,
  );

  /// Para el reporte: claves cortas, porque un viaje largo junta cientos.
  Map<String, dynamic> aMapa() => {
    't': t,
    'kmh': double.parse(kmh.toStringAsFixed(1)),
    'rpm': rpm?.round(),
    'marcha': marcha,
    'prom': double.parse(prominencia.toStringAsFixed(1)),
    'db': double.parse(nivel.toStringAsFixed(1)),
    'bandas': [
      for (final b in bandas) double.parse(b.toStringAsExponential(3)),
    ],
    'marchas': [
      for (final m in porMarcha)
        m == null ? null : double.parse(m.toStringAsFixed(1)),
    ],
    'picos': picos,
  };
}

/// Las ventanas del micrófono en la base (`sitd-37`).
class RegistroDeAudio {
  final Base base;

  RegistroDeAudio(this.base);

  void guardar(int viaje, VentanaAudio v) {
    base.db.execute(
      'INSERT INTO audio (viaje, t, kmh, rpm, marcha, prominencia, nivel, hz, '
      'bandas, marchas, picos) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        viaje,
        v.t,
        v.kmh,
        v.rpm,
        v.marcha,
        v.prominencia,
        v.nivel,
        v.hz,
        v.bandas.join(','),
        v.porMarcha.map((m) => m == null ? '' : m.toStringAsFixed(1)).join(','),
        v.picos.join(','),
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
          marcha: f['marcha'] as int?,
          prominencia: (f['prominencia'] as num).toDouble(),
          nivel: (f['nivel'] as num).toDouble(),
          hz: f['hz'] as int,
          bandas: (f['bandas'] as String)
              .split(',')
              .where((x) => x.isNotEmpty)
              .map(double.parse)
              .toList(),
          porMarcha: _numeros(f['marchas'] as String?),
          picos: _numeros(f['picos'] as String?).whereType<double>().toList(),
        ),
      )
      .toList();

  int cuantas() =>
      base.db.select('SELECT COUNT(*) AS n FROM audio').first['n'] as int;
}

/// «1.5,,3» → [1.5, null, 3.0]; vacío → [].
List<double?> _numeros(String? texto) => texto == null || texto.isEmpty
    ? const []
    : [for (final x in texto.split(',')) x.isEmpty ? null : double.parse(x)];
