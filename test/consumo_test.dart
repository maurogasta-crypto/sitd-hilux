import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/combustible/carga.dart';
import 'package:sitd_hilux/features/combustible/consumo.dart';

Carga carga(
  int dia,
  double litros,
  double odo, {
  bool lleno = true,
  double? costo,
  String moneda = 'UYU',
}) => Carga(
  t: dia * 86400000,
  litros: litros,
  odoTablero: odo,
  tanqueLleno: lleno,
  costo: costo,
  moneda: moneda,
);

void main() {
  group('calcularConsumo', () {
    test('sin cargas no hay nada, y eso no es un cero', () {
      final c = calcularConsumo([]);
      expect(c.hayDatos, isFalse);
      expect(c.litrosCada100, isNull);
      expect(c.ultima, isNull);
      expect(c.autonomia(80), isNull);
    });

    // La primera carga nunca da consumo: no se sabe con cuánto se venía
    // andando. Mostrar un número ahí sería inventarlo.
    test('una sola carga todavia no dice nada', () {
      expect(calcularConsumo([carga(1, 60, 254300)]).litrosCada100, isNull);
    });

    test(
      'de lleno a lleno: los litros de la segunda sobre los km del tramo',
      () {
        // 700 km con 70 litros = 10 L/100 km.
        final c = calcularConsumo([
          carga(1, 60, 254300),
          carga(10, 70, 255000),
        ]);
        expect(c.ventanas.length, 1);
        expect(c.ventanas.single.kmTablero, 700);
        expect(c.ventanas.single.litros, 70);
        expect(c.litrosCada100, closeTo(10, 0.0001));
        expect(c.ventanas.single.kmPorLitro, closeTo(10, 0.0001));
      },
    );

    // Los litros de la carga que ABRE el tramo se quemaron antes. Sumarlos es
    // el error clásico y daría un consumo casi el doble.
    test('los litros de la carga que abre el tramo NO cuentan', () {
      final c = calcularConsumo([
        carga(1, 999, 254300), // un tanque enorme, para que se note
        carga(10, 70, 255000),
      ]);
      expect(c.ventanas.single.litros, 70);
    });

    test('una carga parcial no cierra el tramo, pero sus litros cuentan', () {
      final c = calcularConsumo([
        carga(1, 60, 254300),
        carga(5, 30, 254600, lleno: false),
        carga(10, 40, 255000),
      ]);
      expect(c.ventanas.length, 1);
      expect(c.ventanas.single.litros, 70); // 30 + 40
      expect(c.ventanas.single.kmTablero, 700);
      expect(c.litrosCada100, closeTo(10, 0.0001));
    });

    test('el promedio pesa por kilometro, no por tramo', () {
      // Un tramo corto muy gastador y uno largo económico. El promedio de los
      // promedios daría 15; el bueno, mucho menos.
      final c = calcularConsumo([
        carga(1, 10, 1000),
        carga(2, 20, 1100), // 100 km con 20 L = 20 L/100
        carga(3, 90, 2000), // 900 km con 90 L = 10 L/100
      ]);
      expect(c.ventanas.length, 2);
      expect(c.litrosCada100, closeTo(110 / 1000 * 100, 0.0001));
      expect(c.ultima!.litrosCada100, closeTo(10, 0.0001));
    });

    test('el factor de neumaticos corrige los kilometros del tramo', () {
      final sinFactor = calcularConsumo([
        carga(1, 60, 1000),
        carga(2, 70, 1700),
      ]);
      final conFactor = calcularConsumo([
        carga(1, 60, 1000),
        carga(2, 70, 1700),
      ], k: 1.05);
      // Con neumáticos más grandes se anduvo MÁS de lo que dice el tablero, y
      // por lo tanto se consumió MENOS cada 100 km.
      expect(conFactor.ventanas.single.kmReales, closeTo(735, 0.0001));
      expect(conFactor.litrosCada100, lessThan(sinFactor.litrosCada100!));
    });

    test('un odometro que no avanzo se descarta y no arrastra el error', () {
      final c = calcularConsumo([
        carga(1, 60, 255000),
        carga(2, 70, 254300), // mal tecleado: retrocede
        carga(3, 65, 255700),
      ]);
      // El tramo malo no entra, y el siguiente se mide desde la carga mala en
      // adelante: 255700 - 254300 = 1400 km con 65 L.
      expect(c.ventanas.length, 1);
      expect(c.ventanas.single.kmTablero, 1400);
      expect(c.ventanas.single.litros, 65);
    });

    test('las cargas desordenadas se ordenan por fecha', () {
      final c = calcularConsumo([carga(10, 70, 255000), carga(1, 60, 254300)]);
      expect(c.ventanas.length, 1);
      expect(c.ventanas.single.kmTablero, 700);
    });

    group('plata', () {
      test('cada moneda es un sistema aparte y no se suman', () {
        final c = calcularConsumo([
          carga(1, 60, 1000),
          carga(2, 50, 1500, costo: 3500, moneda: 'UYU'),
          carga(3, 50, 2000, costo: 60, moneda: 'USD'),
        ]);
        expect(c.ventanas[0].costo, {'UYU': 3500.0});
        expect(c.ventanas[1].costo, {'USD': 60.0});
        expect(c.costoPorKm('UYU'), closeTo(3500 / 500, 0.0001));
        expect(c.costoPorKm('USD'), closeTo(60 / 500, 0.0001));
      });

      test('sin costo anotado no se inventa un cero', () {
        final c = calcularConsumo([carga(1, 60, 1000), carga(2, 50, 1500)]);
        expect(c.costoPorKm('UYU'), isNull);
        expect(c.ventanas.single.costoPorKm('UYU'), isNull);
      });

      test('el costo por km ignora los tramos sin precio', () {
        final c = calcularConsumo([
          carga(1, 60, 1000),
          carga(2, 50, 1500), // sin costo
          carga(3, 50, 2000, costo: 3500),
        ]);
        // Sólo el segundo tramo tiene precio: 3500 sobre sus 500 km.
        expect(c.costoPorKm('UYU'), closeTo(7, 0.0001));
      });
    });

    test('la autonomia es la de un tanque lleno, no lo que queda', () {
      final c = calcularConsumo([carga(1, 60, 1000), carga(2, 70, 1700)]);
      // 10 L/100 km con 80 litros de tanque: 800 km.
      expect(c.autonomia(80), closeTo(800, 0.5));
    });
  });

  group('la validacion de una carga', () {
    test('lo que esta bien no tiene problema', () {
      expect(carga(1, 60, 254300).problema, isNull);
    });

    test('litros en cero o negativos', () {
      expect(carga(1, 0, 100).problema, contains('mayor que cero'));
      expect(carga(1, -5, 100).problema, isNotNull);
    });

    test('doscientos litros no entran en el tanque', () {
      expect(carga(1, 250, 100).problema, contains('tanque'));
    });

    test('sin odometro no sirve: es lo que mide el tramo', () {
      expect(carga(1, 60, 0).problema, contains('odómetro'));
    });

    test('una moneda que no es ninguna de las dos', () {
      final c = Carga(t: 0, litros: 60, odoTablero: 100, moneda: 'EUR');
      expect(c.problema, contains('UYU'));
    });

    test('el precio por litro se calcula, no se guarda', () {
      expect(carga(1, 50, 100, costo: 2500).precioPorLitro, 50);
      expect(carga(1, 50, 100).precioPorLitro, isNull);
    });
  });
}
