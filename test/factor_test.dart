import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/odometro/factor.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';

ParCalibracion par(double tablero, double gps) =>
    ParCalibracion(kmTablero: tablero, kmGps: gps);

void main() {
  group('factorRobusto', () {
    test('sin pares devuelve null en vez de un numero inventado', () {
      expect(factorRobusto([]), isNull);
    });

    test('los tramos cortos no cuentan', () {
      // El odometro del tablero avanza de a 1 km: en 5 km el error de lectura
      // es del 20 % y domina sobre lo que se quiere medir.
      expect(factorRobusto([par(5, 5.3), par(8, 8.4)]), isNull);
    });

    test('neumatico mas grande: el tablero marca de menos, k > 1', () {
      final f = factorRobusto([par(100, 105), par(200, 210), par(150, 157.5)])!;
      expect(f.k, closeTo(1.05, 1e-9));
      expect(f.errorPorcentual, closeTo(5.0, 1e-6));
      expect(f.pares, 3);
      expect(f.dispersion, closeTo(0, 1e-9));
    });

    test('neumatico mas chico: k < 1', () {
      final f = factorRobusto([par(100, 96), par(200, 192)])!;
      expect(f.k, closeTo(0.96, 1e-9));
      expect(f.errorPorcentual, closeTo(-4.0, 1e-6));
    });

    test('UN odometro mal anotado no mueve la mediana', () {
      // Esto es lo que justifica usar la mediana y no minimos cuadrados: con
      // pocos pares, un solo error de tipeo arruinaria el factor por meses.
      final limpios = [par(100, 105), par(120, 126), par(90, 94.5)];
      final conError = [...limpios, par(100, 180)]; // se anoto cualquier cosa

      final k1 = factorRobusto(limpios)!.k;
      final k2 = factorRobusto(conError)!.k;
      expect(k2, closeTo(k1, 0.01), reason: 'la mediana aguanta el disparate');

      final mc = factorMinimosCuadrados(conError)!.k;
      expect(
        (mc - k1).abs(),
        greaterThan(0.05),
        reason: 'y los minimos cuadrados no: por eso no son el metodo',
      );
    });

    test('la dispersion delata datos sucios', () {
      final limpio = factorRobusto([
        par(100, 105),
        par(200, 210),
        par(50, 52.5),
      ])!;
      final sucio = factorRobusto([par(100, 105), par(200, 250), par(50, 45)])!;
      expect(limpio.dispersion, lessThan(0.01));
      expect(sucio.dispersion, greaterThan(0.03));
    });

    test('aReal y aTablero son inversas', () {
      final f = factorRobusto([par(100, 107)])!;
      expect(f.aTablero(f.aReal(250)), closeTo(250, 1e-9));
      expect(f.aReal(100), closeTo(107, 1e-9));
    });

    test('numero par de pares: la mediana promedia los dos del medio', () {
      final f = factorRobusto([
        par(100, 100),
        par(100, 102),
        par(100, 104),
        par(100, 106),
      ])!;
      expect(f.k, closeTo(1.03, 1e-9));
    });

    test('valores imposibles se saltean sin romper', () {
      final f = factorRobusto([
        par(100, 105),
        par(100, 0), // GPS en cero: el viaje no se registro
        par(100, double.nan),
        par(double.infinity, 100),
        par(200, 210),
      ])!;
      expect(f.k, closeTo(1.05, 1e-9));
      expect(f.pares, 2);
    });

    test('si todo lo que hay es basura, devuelve null', () {
      expect(factorRobusto([par(100, 0), par(100, double.nan)]), isNull);
    });
  });

  group('factorMinimosCuadrados', () {
    test('con datos limpios coincide con el robusto', () {
      final pares = [par(100, 105), par(200, 210), par(150, 157.5)];
      expect(
        factorMinimosCuadrados(pares)!.k,
        closeTo(factorRobusto(pares)!.k, 1e-9),
      );
    });

    test('sin pares utilizables devuelve null', () {
      expect(factorMinimosCuadrados([par(5, 5)]), isNull);
    });
  });
}
