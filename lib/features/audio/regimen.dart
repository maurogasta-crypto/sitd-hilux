/// Las RPM del motor por lo que escucha el micrófono (`sitd-37`, etapa E).
///
/// Lo pidió Mauro el 2026-10-14 («vamos con la etapa E»), después de descartar
/// leer el alternador por el cargador: la ondulación del alternador anda por
/// los 1.000 a 4.000 Hz y el cargador de 12 a 5 V existe justamente para
/// borrarla. El MOTOR, en cambio, se oye: un 4 cilindros de 4 tiempos explota
/// dos veces por vuelta, así que el encendido suena a `RPM / 30` hertz —25 Hz a
/// ralentí (750 RPM), 133 Hz a 4.000— con sus armónicos encima. A 8.000
/// muestras por segundo eso se ve de sobra, que es lo que el acelerómetro, a
/// 50 Hz, no podía: ahí el motor se colaba plegado (ver `MEDICION.md`).
///
/// **Qué se guarda: los números, nunca el sonido.** Esto recibe un segundo de
/// muestras en memoria y devuelve las RPM, cuánto confiar en ellas, el nivel y
/// ocho bandas gruesas. Con ocho bandas no se reconstruye una palabra.
library;

import 'dart:math' as math;

import '../vibracion/espectro.dart';

/// Muestras por segundo que se le piden al micrófono. 8.000 alcanza y sobra:
/// el armónico 8 del encendido a 4.000 RPM son 1.067 Hz, y Nyquist queda en
/// 4.000.
const int hzAudio = 8000;

/// Dónde puede estar el encendido: de un ralentí bajo (600 RPM → 20 Hz) a un
/// motor bien exigido (4.500 RPM → 150 Hz). Afuera de esto no se busca.
const double fMinimaHz = 20;
const double fMaximaHz = 150;

/// Cuántos armónicos se multiplican para elegir la fundamental. Con cuatro, un
/// pico suelto que no es del motor —un zumbido de 50 Hz de la radio, el
/// ventilador— no gana: no tiene sus armónicos alineados.
const int armonicos = 4;

/// Desde cuántos dB por encima del ruido del rango se cree en las RPM. Abajo
/// de esto la ventana se guarda igual, con las bandas, pero sin RPM.
///
/// **Medido, no elegido** (banco, 14-oct-2026): ruido puro da entre 2,7 y
/// 5,3 dB en veinte semillas; un motor sintético con tanto ruido como señal
/// da 20. Diez deja margen de los dos lados. En la camioneta hay que volver a
/// mirarlo con ventanas reales.
const double prominenciaMinimaDb = 10;

/// Bordes de las bandas de audio, en Hz. Por octavas desde 20: el encendido
/// vive en las dos primeras, sus armónicos en las siguientes, y arriba de
/// 1.280 Hz está la ruta y el viento.
const List<double> bordesAudioHz = [
  20,
  40,
  80,
  160,
  320,
  640,
  1280,
  2560,
  4000,
];

/// Cuántas bandas hay. A mano por el mismo motivo que `cantidadDeBandas`.
const int bandasDeAudio = 8;

/// Lo que se saca de un segundo de micrófono.
class LecturaMotor {
  /// Las RPM estimadas, o `null` si la fundamental no se distingue del ruido.
  final double? rpm;

  /// Cuántos dB sobresale la fundamental elegida sobre la mediana del rango.
  final double prominenciaDb;

  /// Nivel de la señal en dBFS (0 = el máximo que entra; −90 = silencio).
  final double nivelDb;

  /// Qué fracción de las muestras tocó el techo. Más de un 1 % y el espectro
  /// miente: lo saturado mete armónicos que no existen.
  final double saturadas;

  /// Energía por banda (raíz de la suma de cuadrados), como la vibración.
  final List<double> bandas;

  const LecturaMotor({
    required this.rpm,
    required this.prominenciaDb,
    required this.nivelDb,
    required this.saturadas,
    required this.bandas,
  });
}

/// Estima el régimen de [pcm] (muestras de 16 bits) tomadas a [hz].
LecturaMotor leerMotor(List<int> pcm, {int hz = hzAudio}) {
  final n = pcm.length;
  if (n < 256) {
    return LecturaMotor(
      rpm: null,
      prominenciaDb: 0,
      nivelDb: -90,
      saturadas: 0,
      bandas: List<double>.filled(bandasDeAudio, 0),
    );
  }
  var media = 0.0;
  var techo = 0;
  for (final m in pcm) {
    media += m;
    if (m.abs() >= 32440) techo++;
  }
  media /= n;
  final x = List<double>.generate(n, (i) => (pcm[i] - media) / 32768.0);
  var suma = 0.0;
  for (final v in x) {
    suma += v * v;
  }
  final rmsTotal = math.sqrt(suma / n);
  final nivel = rmsTotal <= 1e-9 ? -90.0 : 20 * math.log(rmsTotal) / math.ln10;

  final espectro = magnitudes(x);
  final porCasillero = hz / (espectro.length * 2);
  final bandas = _bandas(espectro, porCasillero);

  // Producto de armónicos (en logaritmo, para que no se vaya a cero): para
  // cada candidato f, la suma de log|X| en f, 2f, 3f y 4f. La fundamental del
  // motor tiene a sus armónicos alineados; un ruido suelto, no.
  final kMin = (fMinimaHz / porCasillero).ceil();
  final kMax = (fMaximaHz / porCasillero).floor();
  if (kMax * armonicos >= espectro.length || kMin < 1) {
    return LecturaMotor(
      rpm: null,
      prominenciaDb: 0,
      nivelDb: nivel,
      saturadas: techo / n,
      bandas: bandas,
    );
  }
  final puntaje = <double>[];
  for (var k = kMin; k <= kMax; k++) {
    var s = 0.0;
    for (var h = 1; h <= armonicos; h++) {
      // El armónico h cae en h·k, pero un casillero de error en la
      // fundamental son h casilleros en el armónico: se busca su pico en un
      // entorno que crece con h. Sin esto, a 1.800 RPM el 4.º armónico caía
      // entre dos casilleros, se perdía, y ganaba el doble de la fundamental
      // (el banco lo encontró: leía 3.600).
      final centro = k * h;
      final ancho = (h + 1) ~/ 2;
      var pico = 0.0;
      for (var j = centro - ancho; j <= centro + ancho; j++) {
        if (j > 0 && j < espectro.length && espectro[j] > pico) {
          pico = espectro[j];
        }
      }
      s += math.log(pico + 1e-12);
    }
    puntaje.add(s / armonicos);
  }
  var mejor = 0;
  for (var i = 1; i < puntaje.length; i++) {
    if (puntaje[i] > puntaje[mejor]) mejor = i;
  }
  final ordenado = List<double>.from(puntaje)..sort();
  final mediana = ordenado[ordenado.length ~/ 2];
  // De logaritmo natural de una magnitud a decibeles: 20·log10(e) ≈ 8,686.
  final prominencia = (puntaje[mejor] - mediana) * 20 / math.ln10;

  // Afinado parabólico entre los tres casilleros vecinos: el espaciado es de
  // 0,98 Hz y eso solo serían ±29 RPM de escalón.
  var k = (mejor + kMin).toDouble();
  if (mejor > 0 && mejor < puntaje.length - 1) {
    final a = puntaje[mejor - 1], b = puntaje[mejor], c = puntaje[mejor + 1];
    final d = a - 2 * b + c;
    if (d < 0) k += 0.5 * (a - c) / d;
  }
  final f0 = k * porCasillero;

  return LecturaMotor(
    rpm: prominencia >= prominenciaMinimaDb ? f0 * 30 : null,
    prominenciaDb: prominencia,
    nivelDb: nivel,
    saturadas: techo / n,
    bandas: bandas,
  );
}

List<double> _bandas(List<double> espectro, double porCasillero) {
  final acumulado = List<double>.filled(bandasDeAudio, 0);
  for (var k = 1; k < espectro.length; k++) {
    final f = k * porCasillero;
    for (var b = 0; b < bandasDeAudio; b++) {
      if (f >= bordesAudioHz[b] && f < bordesAudioHz[b + 1]) {
        acumulado[b] += espectro[k] * espectro[k];
        break;
      }
    }
  }
  return [for (final a in acumulado) math.sqrt(a) / espectro.length];
}
