import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/odometro/integrador.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';

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
  group('Acumulador', () {
    // La prueba que sostiene a las otras: en vivo no hay lista, así que el
    // cálculo se hace muestra por muestra. Si alguna vez las dos formas se
    // separan, el kilometraje del viaje deja de coincidir con el que sale de
    // recalcular ese mismo viaje desde sus puntos — y eso no se nota hasta que
    // alguien compara dos números que tendrían que ser iguales.
    test('muestra por muestra da lo mismo que integrar la lista entera', () {
      final muestras = <Muestra>[
        m(0, 0.2), // por debajo del mínimo: cuenta como detenido
        m(1000, 10, lon: -56.19),
        m(2000, 12, lon: -56.18),
        m(3000, 200), // implausible: se descarta
        m(4000, 12, lon: -56.17, precision: 80), // mala señal: se descarta
        m(5000, 11, lon: -56.16),
        m(30000, 11, lon: -56.10), // hueco de 25 s: corta
        m(31000, 11, lon: -56.09),
        m(31000, 11, lon: -56.09), // sello repetido: se descarta
      ];

      final deUnaVez = integrar(muestras);
      final acumulador = Acumulador();
      for (final x in muestras) {
        acumulador.agregar(x);
      }
      final incremental = acumulador.resultado;

      expect(incremental.metros, deUnaVez.metros);
      expect(incremental.metrosHaversine, deUnaVez.metrosHaversine);
      expect(incremental.muestrasUsadas, deUnaVez.muestrasUsadas);
      expect(incremental.muestrasDescartadas, deUnaVez.muestrasDescartadas);
      expect(incremental.cortes, deUnaVez.cortes);
      expect(incremental.msIntegrados, deUnaVez.msIntegrados);
    });

    test('agregar avisa cuál aceptó y cuál no', () {
      final a = Acumulador();
      expect(a.agregar(m(0, 10)), isTrue);
      expect(a.agregar(m(1000, 10, precision: 500)), isFalse);
      expect(a.agregar(m(2000, 10)), isTrue);
      expect(a.resultado.muestrasUsadas, 2);
      expect(a.resultado.muestrasDescartadas, 1);
    });

    test('una muestra con el reloj para atras no mueve el total', () {
      final a = Acumulador();
      a.agregar(m(10000, 10));
      final antes = a.resultado.metros;
      expect(a.agregar(m(9000, 10)), isFalse);
      expect(a.resultado.metros, antes);
      // Y la última sigue siendo la buena: si se hubiera quedado con la vieja,
      // la próxima muestra integraría un dt negativo.
      expect(a.ultima!.t, 10000);
    });

    test('la ultima es la ultima ACEPTADA, no la ultima que llego', () {
      final a = Acumulador();
      a.agregar(m(1000, 10, lon: -56.2));
      a.agregar(m(2000, 300, lon: -56.0)); // implausible
      expect(a.ultima!.t, 1000);
      expect(a.ultima!.lon, -56.2);
    });

    test('un hueco largo corta y no inventa distancia', () {
      final a = Acumulador();
      a.agregar(m(0, 25));
      a.agregar(m(600000, 25, lon: -56.0)); // diez minutos después
      expect(a.resultado.cortes, 1);
      expect(a.resultado.metros, 0);
      expect(a.resultado.metrosHaversine, 0);
      expect(a.resultado.muestrasUsadas, 2);
    });

    test('sin muestras el resultado es todo cero, no un nulo', () {
      final r = Acumulador().resultado;
      expect(r.metros, 0);
      expect(r.muestrasUsadas, 0);
      expect(r.discrepancia, 0);
      expect(Acumulador().ultima, isNull);
    });

    test('a 20 m/s durante 10 s da 200 m', () {
      final a = Acumulador();
      for (var i = 0; i <= 10; i++) {
        a.agregar(m(i * 1000, 20, lon: -56.2 + i * 0.0002));
      }
      expect(a.resultado.metros, closeTo(200, 0.001));
      expect(a.resultado.msIntegrados, 10000);
    });
  });
}
