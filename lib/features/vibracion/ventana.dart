import 'espectro.dart';

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
/// un desbalanceo a 60 km/h está alrededor de 8 Hz y a 110 alrededor de 15. Si
/// se mezclaran, el mismo defecto aparecería como energía en media docena de
/// bandas y nunca se repetiría igual.
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

  const VentanaVibracion({
    required this.t,
    required this.cubeta,
    required this.hz,
    required this.muestras,
    required this.rms,
    required this.pico,
    required this.bandas,
  });

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
}) {
  if (magnitud.length < minimoDeMuestras) return null;
  final duracion = tFin - tInicio;
  if (duracion <= 0) return null;

  final hz = (magnitud.length - 1) * 1000 / duracion;
  if (!hz.isFinite || hz <= 1) return null;

  final centrada = centrar(magnitud);
  return VentanaVibracion(
    t: tFin,
    cubeta: cubeta,
    hz: hz,
    muestras: magnitud.length,
    rms: rms(centrada),
    pico: pico(centrada),
    bandas: energiaPorBanda(magnitudes(centrada), hz),
  );
}
