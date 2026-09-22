import 'dart:math' as math;

/// Los bordes de las bandas, en hertz.
///
/// **Por qué éstos y no bandas parejas.** Lo que se busca tiene frecuencia
/// proporcional a las vueltas de la rueda: con la rueda medida de esta
/// camioneta (76 cm bajo carga, ver `rueda.dart`) un desbalanceo a 60 km/h
/// está en **6,98 Hz** y a 110 km/h en **12,80 Hz**. La zona de 4 a 17 Hz es
/// donde vive lo mecánico que gira a la velocidad de la rueda —el desbalanceo,
/// la ovalización, los semiejes—, así que ahí las bandas son angostas; abajo
/// de 2 Hz está el bamboleo de la suspensión y el camino, que cambia con el
/// terreno y no dice nada de la mecánica, y arriba de 17 Hz el acelerómetro de
/// un teléfono ya está midiendo el propio soporte.
///
/// **Ojo con dos afirmaciones que este comentario hacía y eran falsas**, las
/// dos encontradas auditando el 2026-09-22:
///
/// Decía «8 Hz a 60 km/h y 15 a 110». Esos números salían de una cubierta
/// genérica, de antes de que Mauro midiera la suya, y están un 15 y un 17 %
/// por encima de los reales. Ahora la cuenta sale de `rueda.dart`, que es el
/// único lugar donde vive el diámetro, y hay una prueba que la fija.
///
/// Y decía que el **cardán** vivía en esta zona. No: el cardán gira unas 3,58
/// veces por cada vuelta de rueda, así que **se sale de la banda de 17 Hz
/// arriba de unos 41 km/h** y de todo el espectro arriba de unos 60. Con este
/// muestreo el cardán sólo es observable andando despacio, y eso no estaba
/// dicho en ningún lado.
///
/// **Y el borde de arriba se pasa de Nyquist.** Muestreando a 49,85 Hz —que es
/// lo que entrega este teléfono midiendo un viaje— el techo del espectro son
/// 24,93 Hz, así que los últimos 0,07 Hz de la banda 17-25 no existen. Es
/// chico y no cambia nada; está dicho para que nadie lo descubra dos veces.
const List<double> bordesHz = [0.5, 2, 4, 6, 8, 10, 13, 17, 25];

/// Cuántas bandas hay: los huecos que dejan los bordes de arriba. Escrito a
/// mano y no derivado de `bordesHz.length` porque Dart no deja leer el largo
/// de una lista en una constante — si se agrega un borde, este número sube en
/// la misma línea, y el banco lo comprueba.
///
/// Un vector de vibración tiene exactamente esta medida, y comparar dos de
/// medidas distintas no tiene sentido.
const int cantidadDeBandas = 8;

/// Magnitudes del espectro de [muestras], hasta Nyquist.
///
/// Las muestras entran **ya centradas** (sin su media): la componente continua
/// de un acelerómetro es la gravedad, que es enorme comparada con lo que se
/// quiere medir y taparía todo lo demás.
///
/// Se aplica una ventana de Hann antes de transformar. Sin ella, cortar cinco
/// segundos de una vibración continua mete un escalón en los extremos, y ese
/// escalón se reparte por todo el espectro —fuga— haciendo aparecer energía en
/// bandas donde no hay nada.
List<double> magnitudes(List<double> muestras) {
  final n = muestras.length;
  if (n < 4) return const [];

  // Se rellena con ceros hasta la próxima potencia de dos. No agrega
  // información —no se puede inventar resolución— pero deja usar la FFT
  // rápida sin tirar muestras, que es lo que haría recortar.
  var largo = 1;
  while (largo < n) {
    largo *= 2;
  }

  final re = List<double>.filled(largo, 0);
  final im = List<double>.filled(largo, 0);
  for (var i = 0; i < n; i++) {
    final hann = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    re[i] = muestras[i] * hann;
  }

  _fft(re, im);

  final mitad = largo ~/ 2;
  return List<double>.generate(
    mitad,
    (k) => math.sqrt(re[k] * re[k] + im[k] * im[k]),
  );
}

/// Energía por banda, en las mismas unidades que la señal de entrada.
///
/// [hz] es la frecuencia de muestreo **medida**, no la pedida: un teléfono
/// nunca entrega exactamente lo que se le pidió, y usar el número teórico
/// correría todas las bandas. A 45 Hz reales en vez de 50, una banda de 8 Hz
/// estaría mirando 7,2.
List<double> energiaPorBanda(List<double> espectro, double hz) {
  final bandas = List<double>.filled(cantidadDeBandas, 0);
  if (espectro.isEmpty || !hz.isFinite || hz <= 0) return bandas;

  // Cada casillero del espectro cubre `hz / largoTotal` hertz, y el espectro
  // que llega es la mitad de ese largo.
  final porCasillero = hz / (espectro.length * 2);
  final acumulado = List<double>.filled(cantidadDeBandas, 0);

  for (var k = 1; k < espectro.length; k++) {
    final f = k * porCasillero;
    for (var b = 0; b < cantidadDeBandas; b++) {
      if (f >= bordesHz[b] && f < bordesHz[b + 1]) {
        acumulado[b] += espectro[k] * espectro[k];
        break;
      }
    }
  }

  for (var b = 0; b < cantidadDeBandas; b++) {
    // Raíz de la suma de cuadrados: queda en unidades de aceleración y no de
    // energía, que es lo que se puede leer en una pantalla y comparar contra
    // el RMS de la ventana sin hacer cuentas de cabeza.
    bandas[b] = math.sqrt(acumulado[b]) / espectro.length;
  }
  return bandas;
}

/// Cooley-Tukey de base 2, en su lugar. Sin dependencias: son cuarenta líneas
/// y traerse un paquete para esto sería el único paquete del proyecto que no
/// habla con el sistema operativo.
void _fft(List<double> re, List<double> im) {
  final n = re.length;

  // Permutación por inversión de bits.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }

  for (var largo = 2; largo <= n; largo <<= 1) {
    final angulo = -2 * math.pi / largo;
    final wRe = math.cos(angulo);
    final wIm = math.sin(angulo);
    for (var i = 0; i < n; i += largo) {
      var curRe = 1.0;
      var curIm = 0.0;
      for (var j = 0; j < largo ~/ 2; j++) {
        final aRe = re[i + j];
        final aIm = im[i + j];
        final bRe =
            re[i + j + largo ~/ 2] * curRe - im[i + j + largo ~/ 2] * curIm;
        final bIm =
            re[i + j + largo ~/ 2] * curIm + im[i + j + largo ~/ 2] * curRe;
        re[i + j] = aRe + bRe;
        im[i + j] = aIm + bIm;
        re[i + j + largo ~/ 2] = aRe - bRe;
        im[i + j + largo ~/ 2] = aIm - bIm;
        final nuevoRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = nuevoRe;
      }
    }
  }
}

/// Valor eficaz de la señal ya centrada.
double rms(List<double> x) {
  if (x.isEmpty) return 0;
  var suma = 0.0;
  for (final v in x) {
    suma += v * v;
  }
  return math.sqrt(suma / x.length);
}

/// El valor absoluto más grande. Un pozo se ve acá antes que en el RMS.
double pico(List<double> x) {
  var p = 0.0;
  for (final v in x) {
    if (v.abs() > p) p = v.abs();
  }
  return p;
}

/// Le saca la media a la señal. Para un acelerómetro, la media **es la
/// gravedad**: sin esto, el primer casillero del espectro se lleva todo.
List<double> centrar(List<double> x) {
  if (x.isEmpty) return const [];
  var suma = 0.0;
  for (final v in x) {
    suma += v;
  }
  final media = suma / x.length;
  return [for (final v in x) v - media];
}
