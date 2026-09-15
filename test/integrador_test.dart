import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/odometro/integrador.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';

/// Muestra de conveniencia: buena señal salvo que se diga lo contrario.
Muestra m(
  int tMs,
  double v, {
  double lat = -34.9,
  double lon = -56.2,
  double precision = 5,
  double? precisionVel = 0.3,
}) => Muestra(
  t: tMs,
  lat: lat,
  lon: lon,
  velocidad: v,
  precision: precision,
  precisionVel: precisionVel,
);

void main() {
  group('integrar', () {
    test('sin muestras da cero y no explota', () {
      final r = integrar([]);
      expect(r.metros, 0);
      expect(r.muestrasUsadas, 0);
    });

    test('una sola muestra no alcanza para integrar nada', () {
      final r = integrar([m(0, 20)]);
      expect(r.metros, 0);
      expect(r.msIntegrados, 0);
    });

    test('velocidad constante: 20 m/s durante 10 s son 200 m', () {
      final muestras = [for (var i = 0; i <= 10; i++) m(i * 1000, 20)];
      final r = integrar(muestras);
      expect(r.metros, closeTo(200, 0.001));
      expect(r.muestrasUsadas, 11);
      expect(r.cortes, 0);
      expect(r.msIntegrados, 10000);
    });

    test('rampa lineal: el trapecio da la integral exacta', () {
      // v va de 0 a 10 m/s en 10 s. Area = 10*10/2 = 50 m.
      final muestras = [
        for (var i = 0; i <= 10; i++) m(i * 1000, i.toDouble()),
      ];
      expect(integrar(muestras).metros, closeTo(50, 0.001));
    });

    test('DETENIDO con ruido de GPS no acumula un metro', () {
      // Es el caso que rompe la suma de haversines: el receptor salta pero el
      // vehiculo no se movio. La velocidad Doppler se mantiene por debajo del
      // umbral y la distancia tiene que dar cero.
      final muestras = [
        for (var i = 0; i <= 60; i++)
          m(
            i * 1000,
            0.2,
            lat: -34.9 + (i.isEven ? 0.00002 : -0.00002),
            lon: -56.2 + (i.isEven ? -0.00002 : 0.00002),
          ),
      ];
      final r = integrar(muestras);
      expect(r.metros, 0, reason: 'la integracion Doppler no debe acumular');
      expect(
        r.metrosHaversine,
        greaterThan(100),
        reason: 'y el haversine SI acumula: por eso no se usa como fuente',
      );
    });

    test('un hueco largo corta el tramo en vez de puentearlo', () {
      final muestras = [
        m(0, 20),
        m(1000, 20),
        m(120000, 20), // dos minutos despues: un tunel
        m(121000, 20),
      ];
      final r = integrar(muestras);
      expect(r.cortes, 1);
      expect(r.metros, closeTo(40, 0.001)); // 20 m + 20 m, sin el puente
    });

    test('precision horizontal mala: se descarta', () {
      final r = integrar([m(0, 20), m(1000, 20, precision: 80), m(2000, 20)]);
      expect(r.muestrasDescartadas, 1);
      expect(r.muestrasUsadas, 2);
      // Se integra 0 -> 2000 ms de corrido porque el hueco entra en el maximo.
      expect(r.metros, closeTo(40, 0.001));
    });

    test('precision de velocidad mala: se descarta', () {
      final r = integrar([m(0, 20), m(1000, 20, precisionVel: 9), m(2000, 20)]);
      expect(r.muestrasDescartadas, 1);
    });

    test('sin precision de velocidad la muestra se acepta igual', () {
      // Android no siempre la informa; exigirla dejaria telefonos enteros sin
      // odometria.
      final r = integrar([
        m(0, 20, precisionVel: null),
        m(1000, 20, precisionVel: null),
      ]);
      expect(r.muestrasDescartadas, 0);
      expect(r.metros, closeTo(20, 0.001));
    });

    test('velocidad implausible para una camioneta: se descarta', () {
      final r = integrar([m(0, 20), m(1000, 200), m(2000, 20)]);
      expect(r.muestrasDescartadas, 1);
    });

    test('velocidad negativa: se descarta', () {
      final r = integrar([m(0, 20), m(1000, -5), m(2000, 20)]);
      expect(r.muestrasDescartadas, 1);
    });

    test('NaN e infinito: se descartan sin envenenar el total', () {
      final r = integrar([
        m(0, 20),
        m(1000, double.nan),
        m(2000, double.infinity),
        m(3000, 20, precision: double.nan),
        m(4000, 20),
      ]);
      expect(r.metros.isFinite, isTrue);
      expect(r.muestrasDescartadas, 3);
    });

    test('coordenadas fuera de rango: se descartan', () {
      final r = integrar([
        m(0, 20),
        m(1000, 20, lat: 120),
        m(2000, 20, lon: 999),
      ]);
      expect(r.muestrasDescartadas, 2);
    });

    test('dos muestras con el mismo sello de tiempo no dividen por cero', () {
      final r = integrar([m(1000, 20), m(1000, 20), m(2000, 20)]);
      expect(r.metros.isFinite, isTrue);
      expect(r.muestrasDescartadas, 1);
    });

    test('muestras desordenadas dan el mismo resultado que ordenadas', () {
      final ordenadas = [for (var i = 0; i <= 10; i++) m(i * 1000, 15)];
      final revueltas = [...ordenadas]..shuffle();
      expect(
        integrar(revueltas).metros,
        closeTo(integrar(ordenadas).metros, 1e-9),
      );
    });

    test('en linea recta los dos metodos coinciden dentro del 5 %', () {
      // Un grado de latitud son ~111,3 km. A 20 m/s durante 100 s son 2000 m.
      const paso = 20.0 / 111320.0; // grados por segundo
      final muestras = [
        for (var i = 0; i <= 100; i++) m(i * 1000, 20, lat: -34.9 + i * paso),
      ];
      final r = integrar(muestras);
      expect(r.metros, closeTo(2000, 1));
      expect(r.discrepancia, lessThan(0.05));
    });

    test('kilometros es metros sobre mil', () {
      final r = integrar([for (var i = 0; i <= 100; i++) m(i * 1000, 10)]);
      expect(r.kilometros, closeTo(1.0, 0.001));
    });

    test('la lista de entrada no se modifica', () {
      final muestras = [m(2000, 20), m(0, 20), m(1000, 20)];
      final antes = muestras.map((x) => x.t).toList();
      integrar(muestras);
      expect(muestras.map((x) => x.t).toList(), antes);
    });
  });

  group('haversine', () {
    test('la misma posicion da cero', () {
      expect(haversine(m(0, 0), m(1000, 0)), closeTo(0, 1e-9));
    });

    test('un grado de latitud son unos 111 km', () {
      final d = haversine(m(0, 0, lat: 0), m(1000, 0, lat: 1));
      expect(d, closeTo(111195, 500));
    });
  });
}
