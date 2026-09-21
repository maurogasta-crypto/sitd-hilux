import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/odometro/validacion_odometro.dart';

void main() {
  group('el odómetro se compara contra lo que midió el GPS', () {
    test('EL CASO REAL: 4055086 no entra, y propone el número que era', () {
      /* El viaje del 2026-09-20 se cerró con un cinco de más. Quedó guardado,
         se subió a la nube y se descubrió tres días después leyendo el
         respaldo con los ojos. */
      final r = revisarOdometro(
        odoInicial: 404988,
        odoFinal: 4055086,
        kmGps: 103.1997,
      );
      expect(r.veredicto, Veredicto.imposible);
      expect(r.entra, isFalse);
      expect(r.sugerido, 405086);
      expect(r.mensaje, contains('103'));
    });

    test('y el valor corregido sí entra', () {
      expect(
        revisarOdometro(
          odoInicial: 404988,
          odoFinal: 405086,
          kmGps: 103.1997,
        ).veredicto,
        Veredicto.bien,
      );
    });

    test('un odómetro que va para atrás es imposible', () {
      expect(
        revisarOdometro(odoInicial: 500, odoFinal: 400, kmGps: 50).veredicto,
        Veredicto.imposible,
      );
    });

    test(
      'un desvío grande avisa pero deja pasar: decidir por el otro es peor',
      () {
        expect(
          revisarOdometro(
            odoInicial: 1000,
            odoFinal: 1130,
            kmGps: 100,
          ).veredicto,
          Veredicto.sospechoso,
        );
      },
    );

    test('un factor de neumáticos normal no molesta a nadie', () {
      /* 5 % es exactamente lo que este proyecto está midiendo: si avisara acá,
         avisaría en todos los viajes y nadie volvería a leer el cartel. */
      expect(
        revisarOdometro(odoInicial: 1000, odoFinal: 1105, kmGps: 100).veredicto,
        Veredicto.bien,
      );
    });

    test('un tramo corto no se juzga: el odómetro avanza de a 1 km', () {
      // Es el viaje 2 del 2026-09-21: cuatro kilómetros de tablero.
      expect(
        revisarOdometro(
          odoInicial: 405087,
          odoFinal: 405091,
          kmGps: 3.92,
        ).veredicto,
        Veredicto.bien,
      );
    });

    test('sin lectura de salida no hay con qué comparar, y se acepta', () {
      expect(
        revisarOdometro(odoInicial: null, odoFinal: 405086, kmGps: 103).entra,
        isTrue,
      );
    });

    test('sin lectura de llegada tampoco', () {
      expect(
        revisarOdometro(odoInicial: 404988, odoFinal: null, kmGps: 103).entra,
        isTrue,
      );
    });

    test('un viaje que midió cero no explota', () {
      expect(
        revisarOdometro(odoInicial: 1000, odoFinal: 1000, kmGps: 0).entra,
        isTrue,
      );
    });

    test('un negativo no pasa', () {
      expect(
        revisarOdometro(odoInicial: 10, odoFinal: -5, kmGps: 50).veredicto,
        Veredicto.imposible,
      );
    });

    test(
      'si sacar un dígito no arregla nada, no se inventa una sugerencia',
      () {
        final r = revisarOdometro(
          odoInicial: 1000,
          odoFinal: 999999,
          kmGps: 100,
        );
        expect(r.veredicto, Veredicto.imposible);
        expect(r.sugerido, isNull);
      },
    );
  });

  group('qué viaje puede calibrar el factor de neumáticos', () {
    test('el viaje del 2026-09-20 NO califica: tuvo un corte', () {
      expect(
        sirveParaCalibrar(cortes: 1, segundosDelViaje: 7078, muestras: 6574),
        isFalse,
      );
    });

    test('y tampoco sin contar el corte: el GPS vio el 92,9 %', () {
      /* Es lo que marcó Mauro: «no había comenzado a medir desde el inicio».
         Perder un 7 % mete un error más grande que el 5 % que se busca. */
      expect(
        sirveParaCalibrar(cortes: 0, segundosDelViaje: 7078, muestras: 6574),
        isFalse,
      );
    });

    test('con cobertura casi entera, sí', () {
      expect(
        sirveParaCalibrar(cortes: 0, segundosDelViaje: 7078, muestras: 7000),
        isTrue,
      );
    });

    test('un viaje de duración cero no califica ni explota', () {
      expect(
        sirveParaCalibrar(cortes: 0, segundosDelViaje: 0, muestras: 0),
        isFalse,
      );
    });

    test('el umbral está donde dice estar', () {
      expect(coberturaMinima, 0.98);
    });
  });
}
