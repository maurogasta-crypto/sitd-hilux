import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/vibracion/calidad.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';
import 'package:sitd_hilux/features/vibracion/rueda.dart';
import 'package:sitd_hilux/features/vibracion/sacudon.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';

/// El banco de la física de la rueda.
///
/// **Existe porque los números estaban escritos a mano en cuatro comentarios y
/// tres decían cosas distintas.** `espectro.dart` y `ventana.dart` afirmaban
/// «un desbalanceo a 60 km/h está alrededor de 8 Hz y a 110 alrededor de 15», y
/// la rueda medida de esta camioneta da 6,98 y 12,80 — un 15 y un 17 % de más.
/// Venían de una cubierta genérica, de antes de que Mauro midiera la suya.
///
/// Lo que se comprueba acá NO es que el código haga lo que el código hace: son
/// valores calculados a mano de la geometría, escritos como literales. Si
/// alguien cambia el diámetro sin querer, o vuelve a escribir un número
/// redondo «que estaba bien», esto falla.
void main() {
  group('la geometría, contra valores calculados a mano', () {
    test('el diámetro es el MEDIDO bajo carga, no el de catálogo', () {
      /* La cubierta es una 265/70R17: sin peso encima da 80,3 cm. Mauro midió
         76 con la camioneta arriba. Ese 5,3 % de achatamiento es más grande
         que el efecto que busca medir el factor de neumáticos, y es el motivo
         entero por el que ese factor se aprende en vez de calcularse. */
      expect(diametroBajoCarga, 0.76);
      final catalogo = 2 * 0.265 * 0.70 + 17 * 0.0254;
      expect(catalogo, closeTo(0.803, 0.002));
      expect(
        (catalogo - diametroBajoCarga) / catalogo,
        closeTo(0.053, 0.005),
        reason: 'el achatamiento medido tendría que andar por el 5 %',
      );
    });

    test('la circunferencia es pi por el diámetro y nada más', () {
      expect(circunferencia, closeTo(2.3876, 0.0001));
      expect(circunferencia, closeTo(math.pi * 0.76, 1e-12));
    });

    test('LOS CUATRO NÚMEROS QUE ESTABAN MAL', () {
      /* Éste es el caso que motivó el archivo. Los valores de la derecha
         salieron de la cuenta, no del código:

             v (km/h)   f = (v/3,6) / 2,3876      decía el comentario
                60             6,98 Hz                  8 Hz   (+15 %)
                110           12,80 Hz                 15 Hz   (+17 %)
                120           13,96 Hz               14,5 Hz   (+4 %)
                65             7,56 Hz                7,6 Hz   (bien) */
      expect(frecuenciaDeRueda(60), closeTo(6.98, 0.01));
      expect(frecuenciaDeRueda(110), closeTo(12.80, 0.01));
      expect(frecuenciaDeRueda(120), closeTo(13.96, 0.01));
      expect(frecuenciaDeRueda(65), closeTo(7.56, 0.01));

      // Y explícitamente: los viejos NO son el resultado correcto.
      expect((frecuenciaDeRueda(60) - 8).abs(), greaterThan(0.5));
      expect((frecuenciaDeRueda(110) - 15).abs(), greaterThan(1.0));
    });

    test('la cuenta al revés es la inversa exacta', () {
      for (final v in [20.0, 55.0, 87.5, 120.0]) {
        expect(velocidadParaFrecuencia(frecuenciaDeRueda(v)), closeTo(v, 1e-9));
      }
    });

    test('quieto es cero, y no se inventa nada', () {
      expect(frecuenciaDeRueda(0), 0);
    });
  });

  group(
    'qué entra en el espectro a 49,85 Hz, que es lo que mide de verdad',
    () {
      const nyquist = 49.85 / 2;

      test('el 1× de la rueda entra SIEMPRE', () {
        /* Llega a Nyquist recién a 214 km/h. Esta camioneta no llega. */
        expect(velocidadMaximaVisible(nyquist, 1), greaterThan(200));
      });

      test('el 2× —la ovalización— se sale arriba de unos 107 km/h', () {
        expect(velocidadMaximaVisible(nyquist, 2), closeTo(107, 2));
      });

      test('el CARDÁN sólo se ve andando despacio, y eso no estaba dicho', () {
        /* El comentario de `espectro.dart` decía que el cardán vivía en la zona
         de 4 a 17 Hz junto con las ruedas. No: gira 3,58 veces por vuelta de
         rueda, así que se sale de los 17 Hz a unos 41 km/h y del espectro
         entero a unos 60. */
        final r = relacionDiferencialAproximada;
        expect(velocidadMaximaVisible(nyquist, r), closeTo(60, 2));
        expect(velocidadParaFrecuencia(17 / r), closeTo(41, 2));

        // Y con la otra relación posible la conclusión no cambia.
        expect(velocidadMaximaVisible(nyquist, 3.909), closeTo(55, 2));
      });

      test('el MOTOR no entra ni a ralentí: es el hallazgo del 2026-09-22', () {
        /* Encendido de un 4 cilindros de 4 tiempos: dos explosiones por vuelta,
         o sea RPM/30. Dar vuelta la cuenta en Nyquist da el techo en RPM. */
        expect(nyquist * 30, closeTo(748, 1));
        expect(
          750 / 30,
          greaterThan(nyquist),
          reason: 'el ralentí más lento ya está por encima del techo',
        );
      });

      test('y lo que no entra APARECE ABAJO, que es peor que no verlo', () {
        /* Aliasing: una frecuencia f muestreada a fs aparece en
         |f - fs*round(f/fs)|. A 2000 RPM el encendido son 66,7 Hz y cae en
         16,8 — justo adentro de la banda 13-17, donde se busca lo mecánico. */
        const fs = 49.85;
        double alias(double f) => (f - fs * (f / fs).round()).abs();
        expect(alias(2000 / 30), closeTo(16.85, 0.05));
        expect(alias(1600 / 30), closeTo(3.48, 0.05));
        expect(alias(2500 / 30), closeTo(16.4, 0.1));

        // Y los tres caen adentro de alguna banda: por eso contaminan.
        for (final rpm in [1600, 2000, 2500]) {
          final a = alias(rpm / 30);
          expect(a, greaterThan(bordesHz.first));
          expect(a, lessThan(bordesHz.last));
        }
      });
    },
  );

  group('las bandas, contra lo que el muestreo permite', () {
    test('el borde de arriba se pasa de Nyquist, y es poco', () {
      const nyquist = 49.85 / 2;
      expect(bordesHz.last, greaterThan(nyquist));
      expect(bordesHz.last - nyquist, lessThan(0.1));
    });

    test('las bandas NO son parejas, y eso cambia cómo se leen', () {
      /* Los anchos van de 1,5 a 8 Hz. Lo que se guarda es la SUMA de cada
         banda, no la densidad, así que la banda de arriba junta cuatro veces
         más bins que las del medio sólo por ser más ancha. Para el detector
         no importa —compara cada banda contra sí misma— pero para leer un
         vector con los ojos hay que dividir por el ancho. */
      final anchos = [
        for (var i = 0; i < cantidadDeBandas; i++)
          bordesHz[i + 1] - bordesHz[i],
      ];
      expect(anchos, [1.5, 2, 2, 2, 2, 3, 4, 8]);
      expect(anchos.reduce(math.max) / anchos.reduce(math.min), greaterThan(5));
    });

    test('en qué banda cae el desbalanceo de cada cubeta', () {
      /* Es la tabla que explica por qué las cubetas existen: el MISMO defecto
         cae en bandas distintas según la velocidad, así que comparar dos
         velocidades hace que todo sea anomalía. */
      int? bandaDe(double hz) {
        for (var i = 0; i < cantidadDeBandas; i++) {
          if (hz >= bordesHz[i] && hz < bordesHz[i + 1]) return i;
        }
        return null;
      }

      final bandas = [
        for (var c = 0; c <= cubetaMaxima; c++)
          bandaDe(frecuenciaDeRueda(velocidadMinimaKmh + c * 10 + 5)),
      ];
      expect(bandas, [1, 2, 2, 3, 3, 4, 4, 5, 5, 6]);
      expect(
        bandas.toSet().length,
        greaterThan(1),
        reason: 'si cayeran todas en la misma, las cubetas no harían falta',
      );
    });
  });

  group('la resolución del espectro, que NO es el espaciado de bins', () {
    test('sale de cuánto DURÓ la ventana, no de cuántos bins hay', () {
      /* El error clásico: la FFT rellena con ceros hasta la próxima potencia
         de dos —251 muestras pasan a 256— y eso junta los bins. Pero rellenar
         INTERPOLA: no se puede inventar información que la ventana no tomó.
         Lo que separa dos tonos es 1/T, y la ventana de Hann ensancha ese
         lóbulo alrededor de un 50 %. */
      final muestras = <Sacudon>[];
      const fs = 49.85;
      for (var i = 0; i < 251; i++) {
        final u = (i * 1e6 / fs).round();
        muestras.add(
          Sacudon(
            u ~/ 1000,
            9.8 + math.sin(2 * math.pi * 10 * i / fs),
            micros: u,
          ),
        );
      }
      final c = medirCalidad(muestras);

      const duracion = 251 / fs; // 5,035 s
      const espaciadoDeBins = fs / 256; // 0,195 Hz — el número engañoso
      expect(c.resolucionHz, closeTo(1.5 / duracion, 0.005));
      expect(c.resolucionHz, closeTo(0.298, 0.01));
      expect(
        c.resolucionHz,
        greaterThan(espaciadoDeBins),
        reason: 'la resolución real es PEOR que el espaciado de bins',
      );
    });

    test('una ventana más larga resuelve más fino', () {
      List<Sacudon> tanda(int n) {
        final out = <Sacudon>[];
        for (var i = 0; i < n; i++) {
          final u = (i * 1e6 / 100).round();
          out.add(Sacudon(u ~/ 1000, 9.8 + math.sin(i / 8), micros: u));
        }
        return out;
      }

      final corta = medirCalidad(tanda(256)).resolucionHz;
      final larga = medirCalidad(tanda(2048)).resolucionHz;
      expect(larga, lessThan(corta / 4));
    });
  });
}
