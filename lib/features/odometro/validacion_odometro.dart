/// Que un odómetro mal tecleado no entre en silencio.
///
/// ## El caso que lo trajo, con el número
///
/// El viaje del 2026-09-20 se cerró con `404988` al salir y **`4055086`** al
/// llegar. Le sobraba un cinco. Eso da 3.650.098 km en dos horas y nadie dijo
/// nada: el dato quedó guardado, se subió a la nube y se descubrió tres días
/// después leyendo el respaldo con los ojos.
///
/// **Lo que faltaba no era un límite, era una comparación.** El viaje ya tiene
/// al lado los kilómetros que midió el GPS: alcanza con mirar si las dos
/// medidas se parecen. Un odómetro que dice diez veces lo que dice el GPS no
/// es un odómetro, es un dedo.
///
/// ## Y hay una segunda cosa, que Mauro marcó y no es la misma
///
/// «Se puede desestimar ese valor porque no había comenzado a medir desde el
/// inicio». Ese viaje perdió los primeros noventa segundos esperando un modo
/// del GPS que no entregaba, y además estuvo cinco minutos en pausa. Aunque
/// los dos odómetros hubieran estado bien, **ese par no sirve para calibrar**:
/// el GPS no midió el mismo tramo que contó el tablero.
///
/// Son dos filtros distintos y los dos hacen falta. El primero atrapa el
/// error de tecleo cuando todavía se puede corregir; el segundo evita que un
/// viaje bien anotado pero mal medido corra el factor de neumáticos.
library;

/// Qué tan mal está un par de lecturas.
enum Veredicto {
  /// Las dos medidas se parecen. Entra.
  bien,

  /// Se parecen poco pero podría ser real: un tramo con mucha parada, un
  /// odómetro leído con un kilómetro de diferencia. Se avisa y se deja pasar
  /// — decidir por el otro sería peor que el problema.
  sospechoso,

  /// No puede ser: el odómetro va para atrás, o dice un orden de magnitud
  /// distinto del que midió el GPS. No se guarda sin confirmar.
  imposible,
}

/// Lo que se le muestra a quien está tecleando.
class RevisionOdometro {
  final Veredicto veredicto;

  /// En los términos de quien está parado al lado de la camioneta, no en los
  /// del programa.
  final String mensaje;

  /// Cuando el número se parece a un dedo de más, el valor que SÍ cierra. Es
  /// lo que convierte un cartel en un botón: en el caso real, `4055086` con
  /// esto ofrecía `405086`.
  final double? sugerido;

  const RevisionOdometro(this.veredicto, this.mensaje, {this.sugerido});

  bool get entra => veredicto != Veredicto.imposible;
}

/// Cuánto puede alejarse el tablero del GPS antes de que se avise.
///
/// El factor de neumáticos que se busca medir anda por el 5 %. Un 20 % es
/// holgado de sobra para cualquier camioneta y cualquier cubierta, así que
/// pasarlo ya no es «neumáticos distintos»: es otra cosa.
const double desvioQueAvisa = 0.20;

/// Y cuánto antes de que directamente no se acepte. Tres veces —o un tercio—
/// no lo explica ninguna cubierta: es un dígito de más o de menos.
const double desvioImposible = 3.0;

/// Abajo de esto no se compara nada: el odómetro avanza de a 1 km, así que en
/// un tramo corto la diferencia es el redondeo y no un error.
const double kmParaComparar = 5.0;

/// Revisa el par (lectura inicial, lectura final) contra lo que midió el GPS.
///
/// [kmGps] son los kilómetros del viaje. Si no hay lectura inicial, o el GPS
/// no midió nada, no hay con qué comparar y se acepta: un dato a medias vale
/// más que ninguno, y el que calibra ya descarta lo que no sirve.
RevisionOdometro revisarOdometro({
  required double? odoInicial,
  required double? odoFinal,
  required double kmGps,
}) {
  if (odoFinal == null || !odoFinal.isFinite) {
    return const RevisionOdometro(Veredicto.bien, '');
  }
  if (odoFinal < 0) {
    return const RevisionOdometro(
      Veredicto.imposible,
      'Un odómetro no puede ser negativo.',
    );
  }
  if (odoInicial == null || !odoInicial.isFinite) {
    return const RevisionOdometro(Veredicto.bien, '');
  }

  if (odoFinal < odoInicial) {
    return RevisionOdometro(
      Veredicto.imposible,
      'El odómetro de llegada (${_km(odoFinal)}) es MENOR que el de salida '
      '(${_km(odoInicial)}). Un odómetro no va para atrás: probablemente se '
      'traspapeló un dígito.',
      sugerido: _sacandoUnDigito(odoFinal, odoInicial, kmGps),
    );
  }

  final kmTablero = odoFinal - odoInicial;
  if (kmGps < kmParaComparar || kmTablero < kmParaComparar) {
    return const RevisionOdometro(Veredicto.bien, '');
  }

  final razon = kmTablero / kmGps;
  if (razon > desvioImposible || razon < 1 / desvioImposible) {
    return RevisionOdometro(
      Veredicto.imposible,
      'El tablero dice ${_km(kmTablero)} y el GPS midió ${_km(kmGps)} del '
      'MISMO viaje. No pueden ser los dos: revisá el número.',
      sugerido: _sacandoUnDigito(odoFinal, odoInicial, kmGps),
    );
  }
  if ((razon - 1).abs() > desvioQueAvisa) {
    return RevisionOdometro(
      Veredicto.sospechoso,
      'Ojo: el tablero dice ${_km(kmTablero)} y el GPS midió ${_km(kmGps)}. '
      'Se guarda igual —puede ser real— pero si te equivocaste al teclear, '
      'este par va a torcer el factor de neumáticos.',
    );
  }
  return const RevisionOdometro(Veredicto.bien, '');
}

/// El error de tecleo más común es un dígito de más. Se prueba sacando cada
/// uno y se devuelve el primero que deja el viaje en un rango razonable.
///
/// No adivina: propone. Con `4055086` y una salida en `404988`, sacar el
/// tercer dígito da `405086` — exactamente lo que había pasado.
double? _sacandoUnDigito(double odoFinal, double odoInicial, double kmGps) {
  if (kmGps <= 0) return null;
  final entero = odoFinal.truncateToDouble();
  if (entero != odoFinal) return null;
  final texto = entero.toStringAsFixed(0);
  if (texto.length < 2) return null;

  for (var i = 0; i < texto.length; i++) {
    final probado = double.tryParse(
      texto.substring(0, i) + texto.substring(i + 1),
    );
    if (probado == null || probado < odoInicial) continue;
    final km = probado - odoInicial;
    if (km < kmParaComparar) continue;
    final razon = km / kmGps;
    if ((razon - 1).abs() <= desvioQueAvisa) return probado;
  }
  return null;
}

String _km(double v) =>
    '${v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 1)} km';

/// ## El segundo filtro: qué viaje puede calibrar
///
/// Un par sirve para aprender el factor sólo si **el GPS midió el mismo tramo
/// que contó el tablero**. Si el viaje se pausó, o si tardó en enganchar el
/// receptor, faltan kilómetros del lado del GPS y el factor sale más chico sin
/// que nada avise — que es la peor forma de equivocarse.
///
/// [segundosDelViaje] es lo que duró de punta a punta; [muestras], cuántas
/// posiciones se aceptaron. **A 1 Hz** —que es lo que pide este proyecto— una
/// muestra es un segundo medido, así que el cociente es la cobertura. Si algún
/// día cambia la cadencia, este cálculo cambia con ella.
bool sirveParaCalibrar({
  required int cortes,
  required int segundosDelViaje,
  required int muestras,
}) {
  if (cortes > 0) return false;
  if (segundosDelViaje <= 0) return false;
  return muestras / segundosDelViaje >= coberturaMinima;
}

/// Qué proporción del viaje tuvo que ver el GPS.
///
/// Es exigente a propósito y el número sale de lo que se quiere medir: el
/// factor de neumáticos anda por el 5 %, así que perder un 7 % del recorrido
/// mete un error MÁS GRANDE que el efecto buscado. El viaje del 2026-09-20
/// llegó al 92,9 % y por eso no califica.
const double coberturaMinima = 0.98;
