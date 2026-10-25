/// La prueba del motor PARADO: ralentí, 1000, 1500 y 2000 RPM (`sitd-45`).
///
/// Lo pidió Mauro el 2026-10-25: «un test con el motor en funcionamiento…
/// registrar el ralentí durante un cierto tiempo y luego pedir que la persona
/// mantenga en el tacómetro la aguja en 1000, 1500 y 2000 rpm durante un
/// cierto tiempo que la misma apk va a designar… y guarda el registro como la
/// referencia para el cruce de informaciones».
///
/// **Por qué parado**: andando, la vibración es motor + rueda + cardán +
/// camino, todo junto. Parado sólo está el motor, y a RPM conocidas — las dice
/// el tacómetro del tablero, que es el único dato de RPM que no sale de este
/// teléfono. Con eso se sabe, para cada régimen, en qué frecuencia vibra y
/// suena el motor en ESTE soporte, y la ronda lo puede restar de un viaje.
///
/// Acá está la parte que se puede probar sin teléfono: los pasos y cómo se
/// resume lo medido. Medir lo hace la pantalla, con el acelerómetro y el
/// micrófono de siempre (`armarVentana` y `leerMotor`), así que la referencia
/// sale de la MISMA cuenta que los viajes.
library;

import '../audio/regimen.dart';
import '../vibracion/ventana.dart';

/// Un paso de la prueba.
class PasoMotor {
  final String titulo;

  /// Lo que tiene que marcar el tacómetro; `null` es ralentí (lo que dé).
  final double? rpm;

  /// Cuánto se mide, en segundos. Lo decide la app, no la persona: así dos
  /// pruebas se pueden comparar.
  final int segundos;

  /// Cuánto se espera antes de medir, para llegar al régimen y estabilizar.
  /// Lo que pasa en esos segundos no se guarda.
  final int acomodo;

  final String instruccion;

  const PasoMotor({
    required this.titulo,
    required this.rpm,
    required this.segundos,
    required this.acomodo,
    required this.instruccion,
  });
}

/// Los pasos, en orden. Un minuto a ralentí —el que más se va a comparar,
/// porque es el que el motor hace solo— y 45 s en cada régimen: nueve
/// ventanas de vibración de 5 s y 45 escuchas, que sobran para una mediana.
/// En total, con el tiempo para llegar a cada régimen, casi cuatro minutos.
const List<PasoMotor> pasosDelMotor = [
  PasoMotor(
    titulo: 'Ralentí',
    rpm: null,
    segundos: 60,
    acomodo: 5,
    instruccion: 'Motor en marcha, sin tocar el acelerador.',
  ),
  PasoMotor(
    titulo: '1000 RPM',
    rpm: 1000,
    segundos: 45,
    acomodo: 10,
    instruccion: 'Acelerá despacio y mantené la aguja del tacómetro en 1000.',
  ),
  PasoMotor(
    titulo: '1500 RPM',
    rpm: 1500,
    segundos: 45,
    acomodo: 10,
    instruccion: 'Mantené la aguja en 1500.',
  ),
  PasoMotor(
    titulo: '2000 RPM',
    rpm: 2000,
    segundos: 45,
    acomodo: 10,
    instruccion: 'Mantené la aguja en 2000.',
  ),
];

/// La cubeta con la que se arman las ventanas de la prueba: no es una
/// velocidad, es «parado». Una ventana de calibración nunca entra a la línea
/// base de los viajes (ni siquiera va a la misma tabla).
const int cubetaParado = -1;

/// Lo que queda de un paso: medianas, no la señal.
///
/// Es lo mismo que guarda un viaje —bandas, picos, RPM oídas, nivel—, para que
/// la ronda lo cruce número contra número. Lleva además si el encendido
/// (`RPM / 30` Hz) apareció entre los picos de la vibración: es lo que dice si
/// el acelerómetro, en este soporte, ve el motor a ese régimen.
Map<String, dynamic> resumirPaso(
  PasoMotor paso,
  List<VentanaVibracion> ventanas,
  List<LecturaMotor> escuchas,
) {
  final rpmOidas = [
    for (final e in escuchas)
      if (e.rpm != null) e.rpm!,
  ];
  final rpmOida = rpmOidas.isEmpty ? null : _mediana(rpmOidas);
  final picosVib = picosFrecuentes([for (final v in ventanas) v.picos]);
  final referencia = paso.rpm ?? rpmOida;
  final encendidoHz = referencia == null ? null : referencia / 30;
  return {
    'paso': paso.titulo,
    if (paso.rpm != null) 'rpmTacometro': paso.rpm,
    'segundos': paso.segundos,
    'ventanas': ventanas.length,
    if (ventanas.isNotEmpty) ...{
      'hz': _r(_mediana([for (final v in ventanas) v.hz]), 1),
      'rms': _r(_mediana([for (final v in ventanas) v.rms]), 4),
      'bandas': _medianaPorPosicion([for (final v in ventanas) v.bandas]),
      'picosVibracion': picosVib,
    },
    'escuchas': escuchas.length,
    'escuchasConRpm': rpmOidas.length,
    if (rpmOida != null) 'rpmOida': _r(rpmOida, 0),
    if (escuchas.isNotEmpty) ...{
      'nivelDb': _r(_mediana([for (final e in escuchas) e.nivelDb]), 1),
      'prominenciaDb': _r(
        _mediana([for (final e in escuchas) e.prominenciaDb]),
        1,
      ),
      'bandasAudio': _medianaPorPosicion([for (final e in escuchas) e.bandas]),
      'picosAudio': picosFrecuentes([for (final e in escuchas) e.picos]),
    },
    if (encendidoHz != null) 'encendidoHz': _r(encendidoHz, 2),
    if (encendidoHz != null && ventanas.isNotEmpty)
      'encendidoEnVibracion': _aparece(picosVib, encendidoHz),
  };
}

/// De muchas listas de picos (frecuencia, fuerza, de a pares), los que más se
/// repiten: frecuencia redondeada a 0,5 Hz y en cuántas ventanas apareció, de
/// a pares, los [cuantos] más frecuentes. Un pico que aparece en una ventana
/// sola es ruido; uno que aparece en todas es la máquina.
List<double> picosFrecuentes(List<List<double>> listas, {int cuantos = 6}) {
  final cuenta = <double, int>{};
  for (final l in listas) {
    final vistos = <double>{};
    for (var i = 0; i + 1 < l.length; i += 2) {
      final f = (l[i] * 2).round() / 2;
      if (vistos.add(f)) cuenta[f] = (cuenta[f] ?? 0) + 1;
    }
  }
  final orden = cuenta.keys.toList()
    ..sort((a, b) {
      final c = cuenta[b]!.compareTo(cuenta[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final f in orden.take(cuantos)) ...[f, cuenta[f]!.toDouble()],
  ];
}

bool _aparece(List<double> picos, double hz) {
  for (var i = 0; i + 1 < picos.length; i += 2) {
    if ((picos[i] - hz).abs() <= hz * 0.05 + 0.5) return true;
  }
  return false;
}

double _mediana(List<double> x) {
  final o = [...x]..sort();
  final n = o.length;
  return n.isOdd ? o[n ~/ 2] : (o[n ~/ 2 - 1] + o[n ~/ 2]) / 2;
}

List<double> _medianaPorPosicion(List<List<double>> filas) {
  if (filas.isEmpty) return const [];
  final largo = filas.first.length;
  final buenas = filas.where((f) => f.length == largo).toList();
  return [
    for (var i = 0; i < largo; i++)
      _r(_mediana([for (final f in buenas) f[i]]), 5),
  ];
}

double _r(double x, int decimales) =>
    double.parse(x.toStringAsFixed(decimales));
