import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';

/// Una senoidal de [f] Hz muestreada a [hz], de [segundos] de largo.
List<double> seno(double f, double hz, double segundos, {double amplitud = 1}) {
  final n = (hz * segundos).round();
  return List<double>.generate(
    n,
    (i) => amplitud * math.sin(2 * math.pi * f * i / hz),
  );
}

/// En qué banda cae una frecuencia, según los bordes declarados.
int bandaDe(double f) {
  for (var b = 0; b < cantidadDeBandas; b++) {
    if (f >= bordesHz[b] && f < bordesHz[b + 1]) return b;
  }
  return -1;
}

void main() {
  group('las bandas', () {
    test('la cantidad escrita a mano coincide con los bordes', () {
      expect(cantidadDeBandas, bordesHz.length - 1);
    });

    test('los bordes van de menor a mayor, sin huecos ni repetidos', () {
      for (var i = 1; i < bordesHz.length; i++) {
        expect(bordesHz[i], greaterThan(bordesHz[i - 1]));
      }
    });
  });

  group('centrar', () {
    // La media de un acelerómetro ES la gravedad: 9,8 contra los 0,2 que se
    // quieren medir. Sin sacarla, el espectro entero es esa constante.
    test('le saca la gravedad a la señal', () {
      final x = centrar([9.8, 10.8, 9.8, 8.8]);
      expect(x.reduce((a, b) => a + b), closeTo(0, 1e-12));
      expect(x[1], closeTo(1, 1e-12));
    });

    test('una lista vacía no explota', () {
      expect(centrar([]), isEmpty);
    });
  });

  group('rms y pico', () {
    test('el rms de una senoidal es la amplitud sobre raiz de dos', () {
      expect(rms(seno(5, 50, 4, amplitud: 2)), closeTo(2 / math.sqrt2, 0.01));
    });

    test('el pico ve el golpe que el rms promedia', () {
      final x = List<double>.filled(500, 0.1)..[250] = 9.0;
      expect(pico(x), 9.0);
      expect(rms(x), lessThan(0.5));
    });
  });

  group('el espectro', () {
    test('una senoidal cae en SU banda y casi nada en las otras', () {
      // 8,6 Hz: adentro de la banda 8-10, lejos de los dos bordes.
      final bandas = energiaPorBanda(magnitudes(seno(8.6, 50, 5)), 50);
      final suya = bandaDe(8.6);
      expect(suya, 4);
      final resto = [
        for (var b = 0; b < cantidadDeBandas; b++)
          if (b != suya) bandas[b],
      ].reduce(math.max);
      expect(bandas[suya], greaterThan(resto * 10));
    });

    test('dos frecuencias distintas caen en dos bandas distintas', () {
      final baja = energiaPorBanda(magnitudes(seno(4.8, 50, 5)), 50);
      final alta = energiaPorBanda(magnitudes(seno(14.5, 50, 5)), 50);
      expect(baja.indexOf(baja.reduce(math.max)), bandaDe(4.8));
      expect(alta.indexOf(alta.reduce(math.max)), bandaDe(14.5));
    });

    test('el doble de amplitud da el doble de energia en su banda', () {
      final uno = energiaPorBanda(magnitudes(seno(8.6, 50, 5)), 50);
      final dos = energiaPorBanda(
        magnitudes(seno(8.6, 50, 5, amplitud: 2)),
        50,
      );
      expect(dos[4], closeTo(uno[4] * 2, uno[4] * 0.05));
    });

    // La trampa de usar la frecuencia teórica en vez de la medida: si el
    // teléfono entrega 45 Hz y se le dice 50, una vibración de 8,6 Hz se lee
    // como 9,6 y puede caer en otra banda.
    test('la frecuencia de muestreo mal declarada corre las bandas', () {
      final muestras = magnitudes(seno(12.5, 45, 5));
      final bien = energiaPorBanda(muestras, 45);
      final mal = energiaPorBanda(muestras, 50);
      expect(bien.indexOf(bien.reduce(math.max)), bandaDe(12.5));
      expect(mal.indexOf(mal.reduce(math.max)), bandaDe(12.5 * 50 / 45));
      expect(
        bien.indexOf(bien.reduce(math.max)),
        isNot(mal.indexOf(mal.reduce(math.max))),
      );
    });

    test('una señal constante no deja energia: es toda gravedad', () {
      final bandas = energiaPorBanda(
        magnitudes(centrar(List<double>.filled(250, 9.8))),
        50,
      );
      for (final b in bandas) {
        expect(b, closeTo(0, 1e-9));
      }
    });

    test('con muy pocas muestras no se inventa un espectro', () {
      expect(magnitudes([1, 2]), isEmpty);
      expect(energiaPorBanda(const [], 50).length, cantidadDeBandas);
    });

    test(
      'una frecuencia de muestreo imposible devuelve ceros, no infinitos',
      () {
        final bandas = energiaPorBanda(magnitudes(seno(8, 50, 5)), 0);
        expect(bandas.every((b) => b == 0), isTrue);
      },
    );
  });
}
