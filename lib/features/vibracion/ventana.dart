import 'dart:math' as math;

import 'espectro.dart';
import 'lineas.dart';

/// Arriba de esto la ventana es una curva: 0,04 rad/s son 2,3° por segundo.
/// Una curva de ruta de 500 m de radio a 100 km/h da 0,056; una esquina de
/// ciudad, diez veces eso. Abajo queda el ruido del giróscopo con el sesgo ya
/// descontado (`sitd-42`).
const double giroDeCurva = 0.04;

/// Desde acá la ventana se midió «rápido» (`sitd-42`): el espectro llega a
/// 100 Hz y el motor ya no se pliega sobre las bandas de la rueda.
const double hzDeMuestreoAlto = 80;

/// 0 = medida a unos 50 Hz, 1 = a 200. **Dos ventanas de clases distintas no
/// se comparan**: a 50 Hz las bandas llevan adentro un pedazo del motor
/// plegado y a 200 no, así que la misma camioneta reparte distinto. Es lo
/// que ya mostró el Redmi 13C a 63 Hz el 10-oct.
int claseDeMuestreo(double hz) => hz >= hzDeMuestreoAlto ? 1 : 0;

/// El ancho de cada cubeta de velocidad, en km/h.
const double anchoDeCubeta = 10;

/// Abajo de esto no se analiza nada.
///
/// En ciudad, entre frenadas, pozos y lomos de burro, la vibración dice del
/// camino y no de la mecánica. Y el dato que se busca tiene frecuencia
/// proporcional a las vueltas de la rueda: abajo de 20 km/h esa frecuencia cae
/// dentro del bamboleo de la suspensión y no se puede separar.
const double velocidadMinimaKmh = 20;

/// La última cubeta junta todo lo que va más rápido. Una Hilux cargada arriba
/// de 120 km/h es rara, y partir esa cola en cubetas de diez dejaría todas
/// vacías — una cubeta sin historia no sirve para comparar nada.
const int cubetaMaxima = 9;

/// En qué cubeta cae una velocidad, o `null` si va demasiado lento.
///
/// **Comparar espectros de velocidades distintas hace que todo sea anomalía**:
/// con la rueda medida de esta camioneta un desbalanceo a 60 km/h está en 6,98
/// Hz y a 110 en 12,80 (ver `rueda.dart`). Si se mezclaran, el mismo defecto
/// aparecería como energía en media docena de bandas y nunca se repetiría
/// igual.
///
/// **Esos dos números decían 8 y 15 hasta el 2026-09-22**, y eran de una
/// cubierta genérica: un 15 y un 17 % de más. La cuenta vive ahora en un solo
/// lugar y tiene su prueba.
int? cubetaDe(double kmh) {
  if (!kmh.isFinite || kmh < velocidadMinimaKmh) return null;
  final c = ((kmh - velocidadMinimaKmh) / anchoDeCubeta).floor();
  return c > cubetaMaxima ? cubetaMaxima : c;
}

/// Cómo se llama una cubeta cuando hay que mostrarla.
String nombreDeCubeta(int cubeta) {
  final desde = velocidadMinimaKmh + cubeta * anchoDeCubeta;
  if (cubeta >= cubetaMaxima) return '${desde.toStringAsFixed(0)}+ km/h';
  return '${desde.toStringAsFixed(0)}-'
      '${(desde + anchoDeCubeta).toStringAsFixed(0)} km/h';
}

/// El resumen de unos segundos de vibración: lo único que se guarda.
///
/// No se guarda la señal cruda del acelerómetro —a 50 Hz por tres ejes son
/// unos 2 MB por hora— y no hace falta: lo que se compara entre viajes es este
/// vector.
class VentanaVibracion {
  final int t;
  final int cubeta;

  /// Frecuencia de muestreo **medida** en esta ventana. Se guarda porque un
  /// teléfono no entrega lo que se le pide, y porque las bandas se calculan
  /// con ella: sin este número, un vector viejo no se puede volver a leer.
  final double hz;

  final int muestras;
  final double rms;
  final double pico;

  /// Energía por banda, en el orden de [bordesHz].
  final List<double> bandas;

  /// Cuánto giraba la camioneta en la ventana, en rad/s, con el sesgo del
  /// giróscopo descontado (`sitd-42`). `null` si el teléfono no tiene
  /// giróscopo. Arriba de [giroDeCurva] la ventana es una CURVA.
  final double? giro;

  /// Cuántos grados se corrió la gravedad, vista desde el teléfono, contra la
  /// posición con la que arrancó el viaje. `null` si todavía no hay
  /// referencia o la fuente no da los ejes.
  final double? angulo;

  /// El teléfono se movió en el soporte durante esta ventana. **No se
  /// compara**: lo que midió es en parte el teléfono moviéndose.
  final bool movido;

  /// Frecuencia y veces sobre la mediana de los picos entre 15 y 100 Hz, de
  /// a pares. Vacío si se midió a 50 Hz: ahí no se ve el motor.
  final List<double> picos;

  /// Las líneas que se repiten, medidas en esta ventana (`sitd-55`): vacío
  /// si se midió a 50 Hz o sin velocidad. Ver `lineas.dart`.
  final Map<Linea, MedidaDeLinea> lineas;

  const VentanaVibracion({
    required this.t,
    required this.cubeta,
    required this.hz,
    required this.muestras,
    required this.rms,
    required this.pico,
    required this.bandas,
    this.giro,
    this.angulo,
    this.movido = false,
    this.picos = const [],
    this.lineas = const {},
  });

  bool get enCurva => (giro ?? 0) >= giroDeCurva;

  VentanaVibracion con({double? giro, double? angulo, bool? movido}) =>
      VentanaVibracion(
        t: t,
        cubeta: cubeta,
        hz: hz,
        muestras: muestras,
        rms: rms,
        pico: pico,
        bandas: bandas,
        giro: giro ?? this.giro,
        angulo: angulo ?? this.angulo,
        movido: movido ?? this.movido,
        picos: picos,
        lineas: lineas,
      );

  Map<String, dynamic> aMapa() => {
    't': t,
    'cubeta': cubeta,
    'hz': hz,
    'muestras': muestras,
    'rms': rms,
    'pico': pico,
    'bandas': bandas,
    if (giro != null) 'giro': double.parse(giro!.toStringAsFixed(4)),
    if (angulo != null) 'angulo': double.parse(angulo!.toStringAsFixed(1)),
    if (movido) 'movido': true,
    if (picos.isNotEmpty) 'picos': picos,
    if (lineas.isNotEmpty) 'lineas': lineasAMapa(lineas),
  };

  bool get completa => bandas.length == cantidadDeBandas;
}

/// Arma la ventana a partir de la señal cruda.
///
/// [magnitud] es el módulo del vector del acelerómetro, muestra por muestra:
/// `sqrt(x² + y² + z²)`. **Se usa el módulo y no un eje** porque no se sabe
/// cómo quedó puesto el teléfono en la cabina — de costado, boca abajo, en un
/// soporte torcido— y con un solo eje el mismo defecto daría números distintos
/// según cómo lo colgaron ese día. El módulo no depende de la orientación.
///
/// Devuelve `null` si la ventana no sirve: pocas muestras, o una frecuencia de
/// muestreo que no se puede calcular.
VentanaVibracion? armarVentana({
  required List<double> magnitud,
  required int tInicio,
  required int tFin,
  required int cubeta,
  int minimoDeMuestras = 64,
  double? kmh,
  int? marcha,
}) {
  if (magnitud.length < minimoDeMuestras) return null;
  final duracion = tFin - tInicio;
  if (duracion <= 0) return null;

  final hz = (magnitud.length - 1) * 1000 / duracion;
  if (!hz.isFinite || hz <= 1) return null;

  final centrada = centrar(magnitud);
  final espectro = magnitudes(centrada);
  return VentanaVibracion(
    t: tFin,
    cubeta: cubeta,
    hz: hz,
    muestras: magnitud.length,
    rms: rms(centrada),
    pico: pico(centrada),
    bandas: energiaPorBanda(espectro, hz),
    picos: claseDeMuestreo(hz) == 1
        ? picosDelEspectro(espectro, hz, hastaHz: math.min(100, hz / 2 - 1))
        : const [],
    // sitd-55: las líneas, con la velocidad media de la ventana y la marcha
    // oída. A 50 Hz no: el motor se pliega y el cardán se sale del techo.
    lineas: claseDeMuestreo(hz) == 1
        ? medirLineas(espectro, hz, kmh: kmh, marcha: marcha)
        : const {},
  );
}
