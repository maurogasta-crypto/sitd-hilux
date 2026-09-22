/// Medir la MEDICIÓN: qué tan confiable es un modo de muestreo y un soporte.
///
/// ## Por qué existe
///
/// Lo pidió Mauro el 2026-09-22, y la frase importa: «no estoy muy seguro de
/// lo confiable de los modos de medición… quizás fijando el teléfono a un
/// punto más fijo, atado a la palanca de cambios». Las dos mitades de esa
/// duda —el modo y el soporte— se contestan igual: **midiéndolas**, sentado en
/// la camioneta, en vez de discutirlas.
///
/// Es la misma idea que el panel de sensores, que entró después de un viaje
/// de siete minutos que dio cero sin que se pudiera saber por qué. Acá el
/// viaje que da cero sería peor: daría números, y no habría forma de saber si
/// significan algo.
///
/// ## Las cinco preguntas que contesta, y por qué son ésas
///
/// **1. ¿A qué frecuencia entrega de verdad?** Android trata el período como
/// una sugerencia. Pidiendo `game` (50 Hz) el Redmi 15 entrega 49,85; pidiendo
/// `fastest` puede entregar cualquier cosa, y eso es exactamente lo que hay
/// que averiguar, porque es lo que decide si el motor se puede ver.
///
/// **2. ¿Entrega PAREJO?** La que nadie mira y la que rompe todo. Una FFT
/// supone que las muestras están igualmente espaciadas; si el sistema entrega
/// a los tirones, el espectro se embarra y el resultado son números con forma
/// de dato. Se mide como `p95 / mediana` del intervalo, y como cuántos huecos
/// hay de más del doble de la mediana.
///
/// **3. ¿Se satura?** Un acelerómetro tiene un fondo de escala. Atado a la
/// palanca de cambios, con el motor en marcha, puede llegar a pegarle — y una
/// señal recortada le inventa armónicos que no existen. Se cuenta cuántas
/// muestras quedaron pegadas al máximo.
///
/// **4. ¿Cuánta señal hay sobre el piso de ruido?** Es lo que compara dos
/// soportes: el que deja pasar más señal útil gana, y la energía total sola no
/// sirve para eso porque un soporte flojo también sacude mucho.
///
/// **5. ¿Se ve algo NÍTIDO?** El pico dominante contra la mediana del
/// espectro. Un soporte rígido da un pico angosto y alto; uno blando lo
/// desparrama. **Este número es el que hay que mirar para comparar soportes**,
/// y es el único de los cinco que no se puede adivinar sin medirlo.
///
/// ## Lo que NO contesta, dicho para que no se le pida
///
/// No dice dónde conviene poner el teléfono. Eso depende de qué se quiera
/// mirar: la palanca de cambios está atornillada a la caja y va a mostrar el
/// motor mucho mejor que el tablero, y al mismo tiempo es un voladizo con
/// resonancia propia y **se mueve cuando uno cambia de marcha**. Para la rueda
/// y la suspensión probablemente sea peor que un punto rígido del piso. No hay
/// un mejor soporte: hay un mejor soporte PARA CADA COSA, y por eso esto mide
/// en vez de recomendar.
///
/// Y no importa nada de Flutter, a propósito: se corre con `dart` a secas,
/// igual que `validacion_odometro.dart`.
library;

import 'dart:math' as math;

import 'espectro.dart';
import 'rueda.dart';
import 'sacudon.dart';

/// Cuántas muestras hacen falta para que los números signifiquen algo.
///
/// Con menos de esto el p95 del intervalo es el segundo valor más grande de un
/// puñado y se mueve solo. No es un número mágico: es «dos segundos a 50 Hz».
const int muestrasMinimas = 100;

/// La velocidad más alta a la que tiene sentido preguntarse si algo se ve.
///
/// Una Hilux cargada arriba de esto es rara, y es el mismo criterio con el que
/// la última cubeta de velocidad junta todo lo que va más rápido.
const double velocidadMasAltaQueImporta = 120;

/// Cuán cerca del máximo tiene que estar un valor para contarlo como
/// recortado contra el fondo de escala.
///
/// **Es una igualdad y no una cercanía, y la diferencia importa.** El primer
/// intento contaba todo lo que estuviera dentro del 0,5 % del máximo, y con
/// eso una senoidal perfectamente limpia daba un 6 % de muestras «saturadas»:
/// una senoidal pasa mucho tiempo cerca de su pico. Lo que de verdad deja el
/// recorte es otra cosa — **valores IDÉNTICOS repetidos**, la meseta plana
/// contra la que pegó el sensor—, y eso una señal analógica muestreada no lo
/// hace nunca. Lo agarró una prueba antes de que el número saliera a pantalla.
const double igualAlTope = 1e-6;

/// Lo que una tanda de muestras dice sobre sí misma.
class Calidad {
  final int muestras;

  /// Frecuencia real de entrega, en hertz. Sale de los sellos de tiempo en
  /// microsegundos, no del período pedido.
  final double hz;

  /// Intervalo entre muestras: la mediana y el percentil 95, en milisegundos.
  final double dtMedianaMs;
  final double dtP95Ms;

  /// Cuántas muestras estimamos que el sistema NO entregó.
  ///
  /// Se cuenta como `redondear(dt / mediana) - 1` en cada intervalo: un hueco
  /// del doble de la mediana es una muestra que faltó, uno del triple son dos.
  ///
  /// **Con mucha irregularidad este número y el de arriba se confunden**, y no
  /// hay forma de separarlos desde acá: un intervalo largo puede ser una
  /// muestra que faltó o una que llegó tarde. Se dice y no se esconde —los dos
  /// números van juntos en pantalla, y si los dos están altos lo que hay que
  /// leer es «este modo no entrega bien», que es la conclusión correcta de
  /// todos modos.
  final int huecos;

  /// Muestras que quedaron pegadas al máximo observado. Si esto no es cero, el
  /// espectro tiene armónicos inventados por el recorte.
  final int saturadas;

  /// Energía total de la señal, sin su media. Sirve para ver si un soporte
  /// transmite más que otro, y **no** para decir cuál es mejor.
  final double rms;

  /// La mediana del espectro: el piso contra el que se mide todo lo demás.
  final double piso;

  /// Dónde está el pico más alto, y cuánto vale.
  final double picoHz;
  final double picoMagnitud;

  /// Con cuánta finura se pueden separar dos frecuencias, en hertz.
  ///
  /// **NO es el espaciado entre bins, y confundirlos es el error clásico.** La
  /// FFT rellena con ceros hasta la próxima potencia de dos, y eso hace que
  /// los bins queden más juntos — pero rellenar INTERPOLA, no agrega
  /// información: no se puede inventar resolución que la ventana no tomó. Lo
  /// que de verdad separa dos tonos es la duración de la ventana, `1/T`, y la
  /// ventana de Hann ensancha ese lóbulo alrededor de un 50 %.
  ///
  /// Sin este número, «pico dominante: 16,82 Hz» se lee con dos decimales de
  /// precisión que no existen. Con una ventana de cinco segundos lo honesto es
  /// «16,8 ± 0,3».
  final double resolucionHz;

  /// Por qué motivo esta medición no sirve, o `null` si sirve.
  final String? problema;

  const Calidad({
    required this.muestras,
    required this.hz,
    required this.dtMedianaMs,
    required this.dtP95Ms,
    required this.dtP5Ms,
    required this.huecos,
    required this.saturadas,
    required this.rms,
    required this.piso,
    required this.picoHz,
    required this.picoMagnitud,
    this.resolucionHz = 0,
    this.problema,
  });

  bool get sirve => problema == null;

  /// Hasta qué frecuencia se puede ver algo. Todo lo de arriba no es que se
  /// vea mal: **aparece abajo, donde no está**.
  double get nyquist => hz / 2;

  /// El percentil 5 del intervalo, en milisegundos.
  final double dtP5Ms;

  /// Cuán desparejo entrega: **0,00 es un metrónomo.**
  ///
  /// Es el ancho de la distribución (p95 menos p5) dividido por la mediana.
  /// Sale relativo para que valga lo mismo a 50 Hz que a 400 y los dos modos
  /// se puedan comparar con un solo número.
  ///
  /// **El primer intento era `p95 / mediana` y se degeneraba.** Cuando los
  /// intervalos toman sólo dos valores —que es exactamente lo que pasa cuando
  /// el sello viene redondeado al milisegundo— la mediana puede caer sobre el
  /// valor ALTO, y entonces el cociente da 1,00 y dice «perfecto» sobre la
  /// medición más desprolija posible. Con el ancho eso no puede pasar: dos
  /// valores distintos dan ancho distinto de cero, siempre.
  double get irregularidad =>
      dtMedianaMs <= 0 ? 0 : (dtP95Ms - dtP5Ms) / dtMedianaMs;

  /// **El número para comparar soportes.** Cuánto sobresale lo que se quiere
  /// ver por encima del ruido de fondo.
  double get nitidez => piso <= 0 ? 0 : picoMagnitud / piso;

  /// El régimen más alto cuyo encendido todavía cae por debajo de Nyquist.
  ///
  /// Un 4 cilindros de 4 tiempos explota dos veces por vuelta: la frecuencia
  /// de encendido es `RPM / 30`. Dar vuelta esa cuenta en el techo del
  /// espectro dice, en la unidad que se lee en un tablero, hasta dónde llega
  /// este modo de medición. A 50 Hz da 747 RPM — o sea, ni el ralentí.
  double get rpmMaximoVisible => nyquist * 30;

  /// La velocidad más alta a la que el desbalanceo de rueda todavía entra en
  /// el espectro, en km/h.
  double get velocidadHastaLaQueSeVeLaRueda =>
      velocidadMaximaVisible(nyquist, 1);

  /// Si el 1× de la rueda se ve a cualquier velocidad que esta camioneta
  /// pueda andar.
  ///
  /// **El umbral sale de la cuenta y no de un número escrito a mano**, que era
  /// lo que había hasta el 2026-09-22: decía «14,5 Hz a 120 km/h» y la rueda
  /// medida de esta camioneta gira a 13,96 a esa velocidad. Cuatro por ciento,
  /// nada grave, y exactamente la clase de número que se copia de un lado a
  /// otro hasta que alguien lo usa para decidir algo.
  bool get laRuedaSeVe =>
      velocidadHastaLaQueSeVeLaRueda >= velocidadMasAltaQueImporta;

  /// Un renglón, para la pantalla y para el registro.
  String get resumen => sirve
      ? '${hz.toStringAsFixed(1)} Hz · Nyquist ${nyquist.toStringAsFixed(1)} Hz '
            '· irregularidad ${irregularidad.toStringAsFixed(2)} · '
            'nitidez ${nitidez.toStringAsFixed(1)}×'
      : problema!;
}

/// Mide una tanda de muestras crudas.
///
/// [muestras] tiene que venir en orden de llegada. No se ordena acá a
/// propósito: si llegaran desordenadas eso **es** el problema que hay que ver,
/// y ordenarlas lo escondería.
Calidad medirCalidad(List<Sacudon> muestras) {
  const vacia = Calidad(
    muestras: 0,
    hz: 0,
    dtMedianaMs: 0,
    dtP95Ms: 0,
    dtP5Ms: 0,
    huecos: 0,
    saturadas: 0,
    rms: 0,
    piso: 0,
    picoHz: 0,
    picoMagnitud: 0,
    problema: 'Todavía no hay suficientes muestras.',
  );
  if (muestras.length < muestrasMinimas) return vacia;

  // ── Los intervalos, en microsegundos ──────────────────────────────────
  final dt = <int>[];
  for (var i = 1; i < muestras.length; i++) {
    dt.add(muestras[i].tMicro - muestras[i - 1].tMicro);
  }
  if (dt.any((d) => d <= 0)) {
    return Calidad(
      muestras: muestras.length,
      hz: 0,
      dtMedianaMs: 0,
      dtP95Ms: 0,
      dtP5Ms: 0,
      huecos: 0,
      saturadas: 0,
      rms: 0,
      piso: 0,
      picoHz: 0,
      picoMagnitud: 0,
      problema:
          'Los sellos de tiempo llegan desordenados o repetidos. Con eso no '
          'se puede medir nada: no es que la señal esté mal, es que no se '
          'sabe cuándo llegó cada muestra.',
    );
  }

  final ordenados = [...dt]..sort();
  final mediana = _percentil(ordenados, 0.5);
  final p95 = _percentil(ordenados, 0.95);
  final p5 = _percentil(ordenados, 0.05);
  /* Cuántas muestras faltaron: un intervalo del doble de la mediana es UNA
     que no llegó, uno del triple son dos. Se cuenta así y no con un umbral
     porque un solo faltante da exactamente 2× — y un umbral puesto en 2,5
     «para no contar de más» se perdía justo el caso más común, que es que
     falte una. Lo encontró una prueba. */
  var huecos = 0;
  if (mediana > 0) {
    for (final d in dt) {
      final faltan = (d / mediana).round() - 1;
      if (faltan > 0) huecos += faltan;
    }
  }

  // La frecuencia sale del tramo COMPLETO y no del promedio de los
  // intervalos: así un hueco pesa lo que tiene que pesar en vez de perderse
  // entre cientos de intervalos buenos.
  final total = muestras.last.tMicro - muestras.first.tMicro;
  final hz = total <= 0 ? 0.0 : (muestras.length - 1) * 1e6 / total;

  // ── La señal ──────────────────────────────────────────────────────────
  final mags = [for (final m in muestras) m.magnitud];
  final media = mags.reduce((a, b) => a + b) / mags.length;
  final centradas = [for (final v in mags) v - media];
  final rms = math.sqrt(
    centradas.map((v) => v * v).reduce((a, b) => a + b) / centradas.length,
  );

  // Saturación: cuántas están pegadas al máximo observado. Se mira el módulo
  // crudo y no el centrado, porque el que se recorta contra el fondo de escala
  // es el valor que entrega el sensor.
  /* Lo que delata al recorte es una MESETA: dos o más muestras seguidas
     pegadas al mismo valor máximo. No alcanza con «igual al máximo» a secas —
     una señal periódica muestreada en fase vuelve a pegarle al mismo pico una
     vez por ciclo, y eso no es saturación sino aritmética. El banco lo agarró
     con una senoidal perfecta que daba un 20 % de «saturadas».

     Una señal analógica no repite su valor en dos muestras CONSECUTIVAS salvo
     que algo la esté recortando. */
  final tope = mags.reduce(math.max);
  var saturadas = 0;
  if (tope > 0) {
    final umbral = tope * igualAlTope;
    bool enElTope(int i) => (tope - mags[i]).abs() <= umbral;
    for (var i = 0; i < mags.length; i++) {
      if (!enElTope(i)) continue;
      final antes = i > 0 && enElTope(i - 1);
      final despues = i < mags.length - 1 && enElTope(i + 1);
      if (antes || despues) saturadas++;
    }
  }

  // ── El espectro ───────────────────────────────────────────────────────
  final esp = magnitudes(centradas);
  /* La resolución sale de cuánto DURÓ la ventana, no de cuántos bins hay. El
     relleno con ceros junta los bins e interpola; la información que separa
     dos tonos es 1/T, y la ventana de Hann ensancha el lóbulo ~50 %. */
  final duracion = total / 1e6;
  final resolucion = duracion <= 0 ? 0.0 : 1.5 / duracion;
  var piso = 0.0;
  var picoHz = 0.0;
  var picoMag = 0.0;
  if (esp.length > 2) {
    /* El bin 0 es la continua y el 1 arrastra lo que queda de la media: los
       dos se saltean. Sin eso, el «pico dominante» de cualquier medición sería
       siempre el bin 0 y esta pantalla no diría nada nunca. */
    final utiles = esp.sublist(2);
    final ord = [...utiles]..sort();
    piso = ord[ord.length ~/ 2];
    for (var k = 0; k < utiles.length; k++) {
      if (utiles[k] > picoMag) {
        picoMag = utiles[k];
        // `esp.length` bins cubren de 0 a Nyquist.
        picoHz = (k + 2) * (hz / 2) / esp.length;
      }
    }
  }

  return Calidad(
    muestras: muestras.length,
    hz: hz,
    dtMedianaMs: mediana / 1000,
    dtP95Ms: p95 / 1000,
    dtP5Ms: p5 / 1000,
    huecos: huecos,
    saturadas: saturadas,
    rms: rms,
    piso: piso,
    picoHz: picoHz,
    picoMagnitud: picoMag,
    resolucionHz: resolucion,
  );
}

double _percentil(List<int> ordenados, double p) {
  if (ordenados.isEmpty) return 0;
  final i = ((ordenados.length - 1) * p).round();
  return ordenados[i].toDouble();
}

/// Qué se puede ver y qué no con este muestreo, en palabras y con los números
/// al lado.
///
/// **No devuelve un puntaje.** Un puntaje junta cosas que se arreglan distinto:
/// que falte frecuencia se arregla pidiendo otro modo, que sobre jitter no se
/// arregla desde la aplicación, y que sature se arregla moviendo el teléfono.
/// Un número solo los taparía a los tres.
List<Hallazgo> leerCalidad(Calidad c, {double velocidadKmh = 0}) {
  if (!c.sirve) return [Hallazgo(Grado.malo, c.problema!)];
  final out = <Hallazgo>[];

  // ── El motor ──────────────────────────────────────────────────────────
  final rpm = c.rpmMaximoVisible;
  if (rpm < 800) {
    out.add(
      Hallazgo(
        Grado.malo,
        'El motor NO se ve: el encendido más lento que entra es de '
        '${rpm.round()} RPM, y el ralentí ya está arriba. Peor todavía, lo '
        'que no entra no desaparece: se pliega y aparece abajo, donde no '
        'está. Con esto no hay tacómetro.',
      ),
    );
  } else if (rpm < 2500) {
    out.add(
      Hallazgo(
        Grado.regular,
        'El motor se ve hasta ${rpm.round()} RPM y de ahí para arriba se '
        'pliega. Sirve para ralentí y poco más.',
      ),
    );
  } else {
    out.add(
      Hallazgo(
        Grado.bueno,
        'El motor se ve hasta ${rpm.round()} RPM. Con esto el tacómetro '
        'sale del acelerómetro, sin micrófono.',
      ),
    );
  }

  // ── La rueda ──────────────────────────────────────────────────────────
  out.add(
    c.laRuedaSeVe
        ? Hallazgo(
            Grado.bueno,
            'La rueda se ve hasta '
            '${c.velocidadHastaLaQueSeVeLaRueda.round()} km/h, o sea siempre.',
          )
        : Hallazgo(
            Grado.malo,
            'La rueda NO se ve entera: arriba de '
            '${(c.nyquist * 8.6).round()} km/h su 1× se sale del espectro.',
          ),
  );

  // ── La regularidad ────────────────────────────────────────────────────
  final faltaron = c.muestras == 0 ? 0.0 : 100 * c.huecos / c.muestras;
  if (c.irregularidad <= 0.3 && faltaron < 1) {
    out.add(
      Hallazgo(
        Grado.bueno,
        'Entrega parejo (irregularidad '
        '${c.irregularidad.toStringAsFixed(2)}, sin faltantes). El espectro se '
        'puede creer.',
      ),
    );
  } else if (c.irregularidad <= 1 && faltaron < 5) {
    out.add(
      Hallazgo(
        Grado.regular,
        'Entrega algo desparejo (irregularidad '
        '${c.irregularidad.toStringAsFixed(2)}, faltó el '
        '${faltaron.toStringAsFixed(1)} %). El espectro se embarra un poco.',
      ),
    );
  } else {
    out.add(
      Hallazgo(
        Grado.malo,
        'Entrega a los tirones (irregularidad '
        '${c.irregularidad.toStringAsFixed(2)}, faltó el '
        '${faltaron.toStringAsFixed(1)} %). Una FFT supone muestras parejas: '
        'con esto los números tienen forma de dato y no lo son.',
      ),
    );
  }

  // ── La saturación ─────────────────────────────────────────────────────
  final porcentaje = c.muestras == 0 ? 0.0 : 100 * c.saturadas / c.muestras;
  if (porcentaje > 0.5) {
    out.add(
      Hallazgo(
        Grado.malo,
        'El ${porcentaje.toStringAsFixed(1)} % de las muestras pega contra el '
        'tope del sensor. Una señal recortada inventa armónicos que no '
        'existen: hay que amortiguar el soporte o moverlo.',
      ),
    );
  }

  // ── La nitidez ────────────────────────────────────────────────────────
  if (c.nitidez >= 8) {
    out.add(
      Hallazgo(
        Grado.bueno,
        'Se ve algo NÍTIDO: el pico está ${c.nitidez.toStringAsFixed(1)} '
        'veces sobre el ruido, en ${c.picoHz.toStringAsFixed(1)} Hz.',
      ),
    );
  } else if (c.nitidez >= 3) {
    out.add(
      Hallazgo(
        Grado.regular,
        'El pico de ${c.picoHz.toStringAsFixed(1)} Hz está '
        '${c.nitidez.toStringAsFixed(1)} veces sobre el ruido. Se distingue, '
        'sin lujo.',
      ),
    );
  } else {
    out.add(
      Hallazgo(
        Grado.malo,
        'No sobresale nada: todo el espectro es parejo '
        '(${c.nitidez.toStringAsFixed(1)}×). O no hay vibración, o el soporte '
        'la está amortiguando.',
      ),
    );
  }

  // ── El cruce con la velocidad, cuando la hay ──────────────────────────
  if (velocidadKmh >= 20) {
    final fRueda = frecuenciaDeRueda(velocidadKmh);
    out.add(
      Hallazgo(
        Grado.dato,
        'A ${velocidadKmh.round()} km/h la rueda gira a '
        '${fRueda.toStringAsFixed(2)} Hz: ahí tendría que estar el '
        'desbalanceo, y en ${(2 * fRueda).toStringAsFixed(2)} Hz la '
        'ovalización. El cardán estaría en '
        '${(fRueda * relacionDiferencialAproximada).toStringAsFixed(1)} Hz, '
        '${fRueda * relacionDiferencialAproximada > c.nyquist ? 'fuera del espectro' : 'adentro'}.',
      ),
    );
  }

  return out;
}

enum Grado { bueno, regular, malo, dato }

class Hallazgo {
  final Grado grado;
  final String texto;
  const Hallazgo(this.grado, this.texto);
}
