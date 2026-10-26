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
/// ## Lo que salió mal en `sitd-37`, y por qué ahora se mira el GPS
///
/// El primer viaje con el micrófono (viaje 19, 14-oct-2026, 469 ventanas)
/// dio RPM que no cerraban con el tacómetro. Cruzadas contra la velocidad
/// del GPS lo dijeron solas: **215 de las 251 lecturas con señal eran la
/// MITAD exacta del régimen de una marcha** (4.ª: 122, 5.ª: 65, 3.ª: 37), y
/// otras 94 estaban clavadas en el piso de la búsqueda, 615 RPM. Dos errores:
///
///  1. **El error de octava.** Un diésel no suena sólo a la frecuencia de
///     encendido: el cigüeñal da una vuelta cada DOS explosiones, y esa
///     vuelta se oye (`RPM / 60`). El producto de armónicos de una
///     frecuencia mitad suma f/2, f, 3f/2 y 2f, y con los armónicos altos
///     más débiles le ganaba a la verdadera. El banco no lo vio porque el
///     motor sintético no tenía esa componente; ahora la tiene (`diesel`).
///  2. **El retumbo de la ruta.** Abajo de 40 Hz el ruido de rodadura y de
///     viento crece, y sin corregirlo cualquier candidato del borde de abajo
///     ganaba por puro volumen. Ahora el espectro se **blanquea**: cada
///     casillero se divide por la mediana de su entorno, y lo que cuenta es
///     cuánto sobresale un pico de lo que lo rodea, no cuán fuerte es.
///
/// Y de esa misma cuenta salió la caja: con R150F y diferencial 3,583 cierran
/// 215 lecturas; con 3,909, 17. **Con la velocidad del GPS ya no se busca en
/// todo el rango**: se prueban las cinco marchas, cada una dice a qué
/// frecuencia tendría que sonar el motor a esa velocidad, y gana la que
/// suena. Si ninguna suena (embrague apretado, punto muerto, cambiando), se
/// busca libre y la lectura sale sin marcha.
///
/// **Qué se guarda: los números, nunca el sonido.** Esto recibe un segundo de
/// muestras en memoria y devuelve las RPM, cuánto confiar en ellas, el nivel y
/// ocho bandas gruesas. Con ocho bandas no se reconstruye una palabra.
library;

import 'dart:math' as math;

import '../vibracion/espectro.dart';
import '../vibracion/rueda.dart';

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

/// Con [trozosParaPromediar] o más segundos promediados (`sitd-47`), la vara
/// baja a 6 dB. Medido con el banco: el ruido solo, promediado de a 8, no
/// pasa de 2,2 dB (de a uno llegaba a 5,2), y un ralentí con la mitad de
/// volumen del que hacía falta da de 6 a 10. Sólo para la prueba parado.
const double prominenciaMinimaPromediadaDb = 6;

/// Cuántos segundos promedia la prueba del motor parado.
const int trozosParaPromediar = 8;

/// Desde cuántos trozos vale la vara más baja: con 4 el ruido llega a 3 dB.
const int trozosParaVaraBaja = 4;

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

/// Las cinco marchas de la caja (R150F), de 1.ª a 5.ª.
///
/// **Deducidas de los datos, no de un catálogo** (viaje 19): son las que
/// hacen cerrar las RPM leídas contra la velocidad del GPS, junto con
/// `relacionDiferencial`. Mientras Mauro no confirme un punto contra el
/// tacómetro, son la mejor hipótesis y no un hecho.
const List<double> relacionesCaja = [3.830, 2.062, 1.436, 1.000, 0.838];

/// Cuántas RPM da el motor por cada km/h en la marcha [marcha] (1 a 5).
///
/// ```
/// 1.ª 95,8   2.ª 51,6   3.ª 35,9   4.ª 25,0   5.ª 21,0
/// ```
double rpmPorKmh(int marcha) =>
    frecuenciaDeRueda(1) *
    60 *
    relacionDiferencial *
    relacionesCaja[marcha - 1];

/// Un motor en marcha y con la camioneta andando no está por debajo de esto
/// (se ahogaría) ni por encima de esto (no se maneja así). Una marcha que
/// pida algo afuera no se prueba: es lo que separa la 2.ª de la 4.ª, que a la
/// misma velocidad suenan a una octava de distancia.
const double rpmMinimaEnMarcha = 900;
const double rpmMaximaEnMarcha = 4300;

/// Cuánto se busca alrededor de lo que predice una marcha. El diámetro bajo
/// carga, el patinamiento y la velocidad que cambió en el segundo mueven la
/// cuenta; en el viaje 19 la mediana del error fue −1,6 %.
const double holguraDeMarcha = 0.05;

/// Con la velocidad, la marcha ganadora vale con menos prominencia que la
/// búsqueda libre —se eligen cinco candidatos y no ciento treinta, así que
/// el azar gana mucho menos—, pero tiene que sacarle ventaja a la segunda.
///
/// **Medido** (banco, 14-oct-2026): con ruido de ruta solo, la mejor marcha
/// sale entre 2,4 y 3,7 dB; un diésel débil a 1.100 RPM, entre 7,5 y 9,3, y
/// la segunda marcha queda al menos 4 dB abajo.
const double prominenciaMinimaEnMarchaDb = 6;
const double margenEntreMarchasDb = 3;

/// En la búsqueda libre, si el doble de la frecuencia elegida suena casi
/// igual (a menos de esto, en dB), se toma el doble: es el error de octava.
const double margenDeOctavaDb = 3;

/// Entre la 2.ª y la 4.ª empatadas gana la de arriba… salvo que la de arriba
/// pida más que esto a esa velocidad (`sitd-40`). En el viaje 25 dos escuchas
/// a 70 y 79 km/h dijeron «2.ª, 3.450 y 3.900 RPM»; el sonido estaba en
/// 1.730, que es la 4.ª. Nadie va en 2.ª a 3.500 RPM a velocidad pareja.
/// Bajó de 3.000 a 2.500 en `sitd-49`: en el viaje 23 del Note 9 quedaban
/// «2.ª» a 51–58 km/h (2.650–2.950 RPM), y Mauro: «nunca circulé a más de
/// 2.200 vueltas, o casi en ningún momento».
const double rpmCreibleArribaDeOctava = 2500;

/// Si, entre dos marchas a una octava, la de arriba ([g], la de más RPM)
/// es creíble a [kmh]. Sin velocidad, como antes: sí.
bool arribaCreible(int g, double? kmh) =>
    kmh == null || kmh * rpmPorKmh(g) <= rpmCreibleArribaDeOctava;

/// La otra mitad de la octava (`sitd-49`): si la marcha elegida pide más de
/// [rpmCreibleArribaDeOctava] a [kmh] y su compañera de octava de ABAJO
/// (la 2.ª → la 4.ª) se probó, gana la compañera. Las dos comparten la serie
/// de armónicos —la fundamental de la 2.ª es el 2.º armónico de la 4.ª—, así
/// que el sonido no las separa: las separa lo creíble. En el viaje 23 del
/// Note 9 (26-oct) salieron 37 «2.ª» entre 42 y 83 km/h, a 3.400–4.100 RPM;
/// Mauro: «nunca circulé a más de 2.200 vueltas». Devuelve la marcha (1 a 5).
int corregirOctavaIncreible(int marcha, List<double?> porMarcha, double? kmh) {
  if (arribaCreible(marcha, kmh)) return marcha;
  for (var g = 1; g <= relacionesCaja.length; g++) {
    if (g == marcha || porMarcha.length < g || porMarcha[g - 1] == null) {
      continue;
    }
    final r = relacionesCaja[g - 1] / relacionesCaja[marcha - 1];
    if (r > 1 / 2.2 && r < 1 / 1.9) return g;
  }
  return marcha;
}

/// Lo que se saca de un segundo de micrófono.
class LecturaMotor {
  /// Las RPM estimadas, o `null` si la fundamental no se distingue del ruido.
  final double? rpm;

  /// La marcha (1 a 5) con la que cerraron las RPM contra la velocidad, o
  /// `null` si se leyeron sin velocidad o sin marcha que suene.
  final int? marcha;

  /// Cuántos dB sobresale la fundamental elegida sobre la mediana del rango.
  final double prominenciaDb;

  /// Nivel de la señal en dBFS (0 = el máximo que entra; −90 = silencio).
  final double nivelDb;

  /// Qué fracción de las muestras tocó el techo. Más de un 1 % y el espectro
  /// miente: lo saturado mete armónicos que no existen.
  final double saturadas;

  /// Energía por banda (raíz de la suma de cuadrados), como la vibración.
  final List<double> bandas;

  /// Lo que sonó cada marcha, en dB sobre la mediana; `null` la que no se
  /// probó. Es el diagnóstico: con esto se ve en la base si la elección fue
  /// clara o pareja.
  final List<double?> porMarcha;

  /// Los picos más salientes del espectro blanqueado, de 15 a 400 Hz:
  /// frecuencia y dB, de a pares. Una docena de números no reconstruye una
  /// palabra, y dicen qué órdenes del motor se oyen de verdad.
  final List<double> picos;

  const LecturaMotor({
    required this.rpm,
    this.marcha,
    required this.prominenciaDb,
    required this.nivelDb,
    required this.saturadas,
    required this.bandas,
    this.porMarcha = const [],
    this.picos = const [],
  });
}

/// Estima el régimen de [pcm] (muestras de 16 bits) tomadas a [hz]. Con
/// [kmh] (la velocidad del GPS) prueba las marchas; sin ella, busca libre.
LecturaMotor leerMotor(List<int> pcm, {int hz = hzAudio, double? kmh}) =>
    leerMotorPromediado([pcm], hz: hz, kmh: kmh);

/// Lo mismo, con VARIOS trozos seguidos del mismo régimen (`sitd-47`): se
/// promedia la potencia de sus espectros antes de buscar. El tono del motor
/// cae siempre en el mismo casillero y el ruido no, así que promediar baja
/// las agujas del ruido y deja al motor solo arriba: es sensibilidad que no
/// depende del micrófono. Sirve parado, con el régimen quieto (la prueba del
/// motor); andando el régimen se mueve y eso lo hace el tacómetro.
/// El nivel, la saturación y las bandas son del último trozo.
LecturaMotor leerMotorPromediado(
  List<List<int>> trozos, {
  int hz = hzAudio,
  double? kmh,
}) {
  final validos = [
    for (final t in trozos)
      if (t.length >= 256) t,
  ];
  if (validos.isEmpty) {
    return LecturaMotor(
      rpm: null,
      prominenciaDb: 0,
      nivelDb: -90,
      saturadas: 0,
      bandas: List<double>.filled(bandasDeAudio, 0),
    );
  }
  // Todos del largo del último: si no, los casilleros no coinciden.
  final pcm = validos.last;
  final n = pcm.length;
  final iguales = [
    for (final t in validos)
      if (t.length == n) t,
  ];
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
  final saturadas = techo / n;

  final ultimo = magnitudes(x);
  final bandas = _bandas(ultimo, hz / (ultimo.length * 2));
  final espectro = iguales.length == 1
      ? ultimo
      : _promedio([
          for (final t in iguales.take(iguales.length - 1)) _espectroDe(t),
          ultimo,
        ]);
  final porCasillero = hz / (espectro.length * 2);
  LecturaMotor sinRpm([double prom = 0]) => LecturaMotor(
    rpm: null,
    prominenciaDb: prom,
    nivelDb: nivel,
    saturadas: saturadas,
    bandas: bandas,
  );

  final kMin = (fMinimaHz / porCasillero).ceil();
  final kMax = (fMaximaHz / porCasillero).floor();
  final hasta = ((rpmMaximaEnMarcha / 30) * armonicos * 1.1 / porCasillero)
      .ceil();
  if (kMin < 1 || math.max(kMax * armonicos, hasta) + 20 >= espectro.length) {
    return sinRpm();
  }
  final a = _Analisis(_blanquear(espectro, porCasillero, hasta), porCasillero);

  // La búsqueda libre, que da también la vara: la mediana de todos los
  // candidatos del rango es «lo que suena cualquier cosa».
  final puntaje = <double>[
    for (var k = kMin; k <= kMax; k++) a.puntaje(k * 1.0),
  ];
  final ordenado = List<double>.from(puntaje)..sort();
  final mediana = ordenado[ordenado.length ~/ 2];
  double enDb(double s) => (s - mediana) * 20 / math.ln10;

  // Las marchas, si hay velocidad.
  final porMarcha = List<double?>.filled(relacionesCaja.length, null);
  final kPorMarcha = List<double>.filled(relacionesCaja.length, 0);
  int? marcha;
  var kMarcha = 0.0;
  var sMarcha = double.negativeInfinity;
  if (kmh != null && kmh > 0) {
    for (var g = 1; g <= relacionesCaja.length; g++) {
      final rpm = kmh * rpmPorKmh(g);
      if (rpm < rpmMinimaEnMarcha || rpm > rpmMaximaEnMarcha) continue;
      final centro = rpm / 30 / porCasillero;
      final ancho = math.max(1, (centro * holguraDeMarcha).ceil());
      var mejorK = centro;
      var mejorS = double.negativeInfinity;
      for (var k = centro.round() - ancho; k <= centro.round() + ancho; k++) {
        final s = a.puntaje(k * 1.0);
        if (s > mejorS) {
          mejorS = s;
          mejorK = k * 1.0;
        }
      }
      porMarcha[g - 1] = enDb(mejorS);
      kPorMarcha[g - 1] = mejorK;
      if (mejorS > sMarcha) {
        sMarcha = mejorS;
        kMarcha = mejorK;
        marcha = g;
      }
    }
  }
  final picos = a.picos(15, 400, 6);
  // La 2.ª suena una octava arriba de la 4.ª a la misma velocidad (2,062
  // veces), y la 1.ª casi una arriba de la 3.ª (2,667: no). Entre dos
  // marchas a una octava, empatadas, gana la de arriba: es el mismo error
  // de octava, y la vuelta del cigüeñal hace sonar a la de abajo.
  final ganadora = marcha;
  if (ganadora != null) {
    for (var g = 1; g <= relacionesCaja.length; g++) {
      final sg = porMarcha[g - 1];
      if (sg == null || g == ganadora) continue;
      final razon = relacionesCaja[g - 1] / relacionesCaja[ganadora - 1];
      if (razon > 1.9 &&
          razon < 2.2 &&
          enDb(sMarcha) - sg <= margenDeOctavaDb &&
          arribaCreible(g, kmh)) {
        marcha = g;
        kMarcha = kPorMarcha[g - 1];
        break;
      }
    }
  }
  if (marcha != null) {
    final abajo = corregirOctavaIncreible(marcha, porMarcha, kmh);
    if (abajo != marcha) {
      marcha = abajo;
      kMarcha = kPorMarcha[abajo - 1];
    }
  }
  // La segunda, sin contar la compañera de octava: esa no es otra hipótesis
  // del motor, es la misma oída una octava abajo.
  final probadas = <double>[
    for (var g = 1; g <= relacionesCaja.length; g++)
      if (porMarcha[g - 1] != null && g != marcha && !_aUnaOctava(g, marcha))
        porMarcha[g - 1]!,
  ]..sort();
  final segunda = probadas.isEmpty ? double.negativeInfinity : probadas.last;
  if (marcha != null &&
      enDb(sMarcha) >= prominenciaMinimaEnMarchaDb &&
      enDb(sMarcha) - segunda >= margenEntreMarchasDb) {
    final k = a.afinar(kMarcha);
    return LecturaMotor(
      rpm: k * porCasillero * 30,
      marcha: marcha,
      prominenciaDb: enDb(sMarcha),
      nivelDb: nivel,
      saturadas: saturadas,
      bandas: bandas,
      porMarcha: porMarcha,
      picos: picos,
    );
  }

  // Libre: la mejor del rango, corregida de octava.
  var mejor = 0;
  for (var i = 1; i < puntaje.length; i++) {
    if (puntaje[i] > puntaje[mejor]) mejor = i;
  }
  var k = (mejor + kMin).toDouble();
  var s = puntaje[mejor];
  // Pegada al borde no es un pico: es el retumbo que sigue bajando.
  final enElBorde = mejor == 0 || mejor == puntaje.length - 1;
  for (var vuelta = 0; vuelta < 2; vuelta++) {
    final doble = k * 2;
    if (doble > kMax * 1.0) break;
    var sDoble = double.negativeInfinity;
    var kDoble = doble;
    for (var j = doble.round() - 1; j <= doble.round() + 1; j++) {
      final sj = a.puntaje(j * 1.0);
      if (sj > sDoble) {
        sDoble = sj;
        kDoble = j * 1.0;
      }
    }
    if ((s - sDoble) * 20 / math.ln10 > margenDeOctavaDb) break;
    k = kDoble;
    s = sDoble;
  }
  // Andando, la libre tampoco pasa de lo creíble (`sitd-54`): en el viaje 24
  // del Note 9 tres escuchas sin marcha dieron 3.461 a 3.543 RPM a 50 y
  // 82 km/h, la octava de arriba de lo que sonaba. Se baja de octava; si
  // abajo no suena, la prominencia lo dice y la lectura sale sin RPM.
  if (kmh != null && kmh > 0) {
    while (k * porCasillero * 30 > rpmCreibleArribaDeOctava && k / 2 >= kMin) {
      final mitad = k / 2;
      var kMitad = mitad;
      var sMitad = double.negativeInfinity;
      for (var j = mitad.round() - 1; j <= mitad.round() + 1; j++) {
        final sj = a.puntaje(j * 1.0);
        if (sj > sMitad) {
          sMitad = sj;
          kMitad = j * 1.0;
        }
      }
      k = kMitad;
      s = sMitad;
    }
  }
  final prominencia = enDb(s);
  final vara = iguales.length >= trozosParaVaraBaja
      ? prominenciaMinimaPromediadaDb
      : prominenciaMinimaDb;
  final vale = prominencia >= vara && !(enElBorde && k == mejor + kMin);
  return LecturaMotor(
    rpm: vale ? a.afinar(k) * porCasillero * 30 : null,
    prominenciaDb: prominencia,
    nivelDb: nivel,
    saturadas: saturadas,
    bandas: bandas,
    porMarcha: porMarcha,
    picos: picos,
  );
}

/// El espectro de un trozo, sin la media (la componente continua).
List<double> _espectroDe(List<int> pcm) {
  final media = pcm.fold<int>(0, (s, m) => s + m) / pcm.length;
  return magnitudes([for (final m in pcm) (m - media) / 32768.0]);
}

/// La raíz de la potencia media, casillero a casillero.
List<double> _promedio(List<List<double>> espectros) {
  final n = espectros.first.length;
  return List<double>.generate(n, (k) {
    var p = 0.0;
    for (final e in espectros) {
      p += e[k] * e[k];
    }
    return math.sqrt(p / espectros.length);
  });
}

bool _aUnaOctava(int g, int? h) {
  if (h == null) return false;
  final r = relacionesCaja[g - 1] / relacionesCaja[h - 1];
  return (r > 1.9 && r < 2.2) || (r > 1 / 2.2 && r < 1 / 1.9);
}

/// Cada casillero dividido por la mediana de su entorno (±8 Hz). Lo que
/// queda es cuánto sobresale de lo que lo rodea: un pico del motor sigue
/// siendo un pico, el retumbo de la ruta deja de serlo.
List<double> _blanquear(List<double> e, double porCasillero, int hasta) {
  final w = math.max(3, (8 / porCasillero).round());
  final fin = math.min(hasta + w, e.length - 1);
  final b = List<double>.filled(fin + 1, 0);
  for (var k = 1; k <= fin; k++) {
    final entorno = <double>[
      for (var j = math.max(1, k - w); j <= math.min(e.length - 1, k + w); j++)
        e[j],
    ]..sort();
    final piso = entorno[entorno.length ~/ 2];
    b[k] = e[k] / (piso + 1e-12);
  }
  return b;
}

class _Analisis {
  final List<double> b;
  final double porCasillero;
  _Analisis(this.b, this.porCasillero);

  /// Producto de armónicos (en logaritmo) del candidato en el casillero
  /// [k]: la media de log|X| en k, 2k, 3k y 4k. El armónico h se busca en un
  /// entorno que crece con h, porque un casillero de error en la fundamental
  /// son h en el armónico (a 1.800 RPM el 4.º caía entre dos y ganaba el
  /// doble: lo encontró el banco en `sitd-37`).
  double puntaje(double k) {
    var s = 0.0;
    for (var h = 1; h <= armonicos; h++) {
      final centro = (k * h).round();
      final ancho = (h + 1) ~/ 2;
      var pico = 0.0;
      for (var j = centro - ancho; j <= centro + ancho; j++) {
        if (j > 0 && j < b.length && b[j] > pico) pico = b[j];
      }
      s += math.log(pico + 1e-12);
    }
    return s / armonicos;
  }

  /// Afinado parabólico entre los vecinos: el espaciado es de 0,98 Hz y eso
  /// solo serían ±29 RPM de escalón.
  double afinar(double k) {
    final a = puntaje(k - 1), c = puntaje(k + 1), m = puntaje(k);
    final d = a - 2 * m + c;
    if (d >= 0) return k;
    final corrido = k + 0.5 * (a - c) / d;
    return (corrido - k).abs() <= 1 ? corrido : k;
  }

  /// Los [cuantos] máximos locales más salientes entre [desde] y [hastaHz],
  /// separados al menos 3 Hz: frecuencia y dB, de a pares.
  List<double> picos(double desde, double hastaHz, int cuantos) {
    final k0 = math.max(1, (desde / porCasillero).ceil());
    final k1 = math.min(b.length - 2, (hastaHz / porCasillero).floor());
    final cand = <int>[
      for (var k = k0; k <= k1; k++)
        if (b[k] > b[k - 1] && b[k] >= b[k + 1] && b[k] > 1) k,
    ]..sort((x, y) => b[y].compareTo(b[x]));
    final elegidos = <int>[];
    for (final k in cand) {
      if (elegidos.every((e) => (e - k).abs() * porCasillero >= 3)) {
        elegidos.add(k);
        if (elegidos.length == cuantos) break;
      }
    }
    return [
      for (final k in elegidos) ...[
        double.parse((k * porCasillero).toStringAsFixed(1)),
        double.parse((20 * math.log(b[k]) / math.ln10).toStringAsFixed(1)),
      ],
    ];
  }
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
