import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/vibracion/analisis.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';

/// Una ventana con las bandas que se le pidan y ruido reproducible encima.
VentanaVibracion v(
  int t,
  int cubeta,
  List<double> bandas, {
  double ruido = 0,
  int semilla = 1,
}) {
  final r = math.Random(semilla);
  return VentanaVibracion(
    t: t,
    cubeta: cubeta,
    hz: 50,
    muestras: 250,
    rms: 0.2,
    pico: 0.9,
    bandas: [for (final b in bandas) b + (r.nextDouble() - 0.5) * 2 * ruido],
  );
}

/// Ocho bandas parejas, que es «lo normal» de esta camioneta en las pruebas.
List<double> normal([double x = 0.10]) => List<double>.filled(8, x);

/// [cuantas] ventanas de un viaje, todas parecidas.
List<VentanaVibracion> viaje(
  int cuantas, {
  int cubeta = 4,
  List<double>? bandas,
  double ruido = 0.004,
  int semilla = 7,
}) => [
  for (var i = 0; i < cuantas; i++)
    v(i * 5000, cubeta, bandas ?? normal(), ruido: ruido, semilla: semilla + i),
];

void main() {
  group('la forma del espectro', () {
    test('suma uno, sea cual sea la intensidad', () {
      for (final x in [0.001, 0.1, 5.0]) {
        final f = formaDelEspectro(normal(x))!;
        expect(f.reduce((a, b) => a + b), closeTo(1, 1e-12));
      }
    });

    test('la misma forma a otra intensidad da exactamente lo mismo', () {
      final a = formaDelEspectro(normal(0.1))!;
      final b = formaDelEspectro(normal(7.3))!;
      for (var i = 0; i < cantidadDeBandas; i++) {
        expect(a[i], closeTo(b[i], 1e-12));
      }
    });

    test('divide por el ancho: una energia pareja NO es una forma pareja', () {
      // Lo guardado es la SUMA de cada banda. La de 17 a 25 Hz tiene 8 Hz de
      // ancho y la de 2 a 4 tiene 2: con la misma suma, la ancha tiene cuatro
      // veces menos por Hz. Sin dividir, pesaría de más en el total.
      expect(anchosDeBanda, [1.5, 2, 2, 2, 2, 3, 4, 8]);
      final f = formaDelEspectro(normal())!;
      expect(f[7], closeTo(f[1] / 4, 1e-12));
      expect(f[0], greaterThan(f[1]));
    });

    test('sin energia, o con un dato roto, no hay forma', () {
      expect(formaDelEspectro(List.filled(8, 0.0)), isNull);
      expect(formaDelEspectro([1, 2, 3]), isNull);
      expect(formaDelEspectro(List.filled(8, double.nan)), isNull);
      expect(formaDelEspectro(List.filled(8, double.infinity)), isNull);
    });
  });

  group('las cubetas de velocidad', () {
    test('abajo del minimo no se analiza nada', () {
      expect(cubetaDe(0), isNull);
      expect(cubetaDe(19.9), isNull);
      expect(cubetaDe(double.nan), isNull);
    });

    test('cada diez km/h es una cubeta', () {
      expect(cubetaDe(20), 0);
      expect(cubetaDe(29.9), 0);
      expect(cubetaDe(30), 1);
      expect(cubetaDe(65), 4);
    });

    test('la ultima junta todo lo que va mas rapido', () {
      expect(cubetaDe(110), cubetaMaxima);
      expect(cubetaDe(180), cubetaMaxima);
    });

    test('el nombre dice el rango, y la ultima dice que es abierta', () {
      expect(nombreDeCubeta(0), '20-30 km/h');
      expect(nombreDeCubeta(4), '60-70 km/h');
      expect(nombreDeCubeta(cubetaMaxima), '110+ km/h');
    });
  });

  group('armar una ventana', () {
    List<double> sacudida(double f, double hz, double segundos) {
      final n = (hz * segundos).round();
      // Con la gravedad adentro, como la entrega el acelerómetro de verdad.
      return List<double>.generate(
        n,
        (i) => 9.8 + 0.3 * math.sin(2 * math.pi * f * i / hz),
      );
    }

    test('con pocas muestras no se inventa nada', () {
      expect(
        armarVentana(
          magnitud: List<double>.filled(10, 9.8),
          tInicio: 0,
          tFin: 5000,
          cubeta: 3,
        ),
        isNull,
      );
    });

    test('un tiempo que no avanza tampoco', () {
      expect(
        armarVentana(
          magnitud: sacudida(8.6, 50, 5),
          tInicio: 5000,
          tFin: 5000,
          cubeta: 3,
        ),
        isNull,
      );
    });

    test(
      'la frecuencia sale de los sellos de tiempo, no de lo que se pidio',
      () {
        // 250 muestras en 5,55 s son 44,9 Hz, no 50: es lo que pasa de verdad.
        final ventana = armarVentana(
          magnitud: sacudida(8.6, 50, 5),
          tInicio: 0,
          tFin: 5550,
          cubeta: 3,
        )!;
        expect(ventana.hz, closeTo(44.9, 0.2));
        expect(ventana.muestras, 250);
      },
    );

    test('la gravedad no se cuela en el espectro', () {
      final ventana = armarVentana(
        magnitud: sacudida(8.6, 50, 5),
        tInicio: 0,
        tFin: 4980,
        cubeta: 3,
      )!;
      expect(ventana.completa, isTrue);
      // El pico de energía está en la banda de 8 a 10 Hz, y el RMS es el de la
      // sacudida (0,3 de amplitud), no el de 9,8 m/s².
      expect(ventana.bandas.indexOf(ventana.bandas.reduce(math.max)), 4);
      expect(ventana.rms, closeTo(0.3 / math.sqrt2, 0.02));
    });
  });

  group('la linea base', () {
    test('sin historia no hay ninguna', () {
      expect(lineaBase({}), isEmpty);
    });

    test('con pocas ventanas existe pero no alcanza', () {
      final base = lineaBase({1: viaje(10)});
      expect(base[4]!.ventanas, 10);
      expect(base[4]!.suficiente, isFalse);
    });

    test('con suficiente historia da la mediana de la FORMA de cada banda', () {
      final base = lineaBase({1: viaje(20), 2: viaje(20, semilla: 99)});
      final esperada = formaDelEspectro(normal())!;
      expect(base[4]!.suficiente, isTrue);
      for (var b = 0; b < cantidadDeBandas; b++) {
        expect(base[4]!.mediana[b], closeTo(esperada[b], 0.005));
        expect(base[4]!.mad[b], greaterThan(0));
      }
    });

    // Sin esto, una falla que empieza y se queda se mete de a poco en «lo
    // normal» hasta dejar de verse. Es el modo de fallar más silencioso que
    // tiene un detector de anomalías.
    test('los viajes que se estan evaluando se dejan afuera', () {
      // El raro tiene que ser raro de FORMA: con todas las bandas al nueve
      // veces —lo que esta prueba usaba hasta `sitd-33`— ahora es el mismo
      // viaje, porque eso es un camino peor y no una camioneta distinta.
      final historia = {
        1: viaje(20),
        2: viaje(20, semilla: 99),
        3: viaje(20, bandas: normal()..[5] = 0.9, semilla: 5),
      };
      expect(lineaBase(historia)[4]!.ventanas, 60);
      expect(lineaBase(historia, excepto: {3})[4]!.ventanas, 40);
      // Y la mediana no se movió con el viaje raro adentro de la excepción.
      expect(
        lineaBase(historia, excepto: {3})[4]!.mediana[5],
        closeTo(formaDelEspectro(normal())![5], 0.005),
      );
    });

    test('cada cubeta arma la suya y no se mezclan', () {
      // Formas distintas, no intensidades distintas: dos intensidades de la
      // misma forma son hoy la misma línea base.
      final base = lineaBase({
        1: viaje(20, cubeta: 2, bandas: normal()..[0] = 0.5),
        2: viaje(20, cubeta: 7, bandas: normal()..[7] = 0.5),
      });
      expect(base.keys.toSet(), {2, 7});
      expect(base[2]!.mediana[0], greaterThan(base[7]!.mediana[0] * 2));
      expect(base[7]!.mediana[7], greaterThan(base[2]!.mediana[7] * 2));
    });
  });

  group('comparar un viaje', () {
    final historia = {
      for (var i = 1; i <= 4; i++) i: viaje(15, semilla: i * 31),
    };

    test('un viaje normal no dispara nada', () {
      final base = lineaBase(historia);
      expect(compararViaje(viaje(15, semilla: 555), base), isEmpty);
    });

    test('una banda que crece se ve, y dice cual y en que cubeta', () {
      final base = lineaBase(historia);
      final malo = normal()..[5] = 0.35; // la banda de 10 a 13 Hz, al triple
      final desvios = compararViaje(viaje(15, bandas: malo), base);
      expect(desvios, isNotEmpty);
      expect(desvios.first.banda, 5);
      expect(desvios.first.cubeta, 4);
      expect(desvios.first.ahora, greaterThan(desvios.first.normal));
      expect(desvios.first.rango, contains('10'));
    });

    // Que vibre MENOS que antes no es una falla mecánica: es un camino mejor,
    // otra carga, o una rueda que se limpió sola.
    test('una banda que BAJA no es una anomalia', () {
      final base = lineaBase(historia);
      final suave = normal()..[5] = 0.001;
      expect(compararViaje(viaje(15, bandas: suave), base), isEmpty);
    });

    // LA PROPIEDAD POR LA QUE SE CAMBIÓ EL DETECTOR (`sitd-33`). Como las
    // proporciones suman uno, que una banda caiga hace subir un poco la parte
    // de las otras siete. Eso no puede disparar un aviso en ninguna.
    test('y que una caiga no hace «subir» a las demás hasta avisar', () {
      final base = lineaBase(historia);
      for (var b = 0; b < cantidadDeBandas; b++) {
        final unaMenos = normal()..[b] = 0.0;
        expect(
          compararViaje(viaje(15, bandas: unaMenos), base),
          isEmpty,
          reason: 'apagar la banda $b no puede parecer una falla en otra',
        );
      }
    });

    test('EL CAMINO ASPERO NO ES UNA ANOMALIA: todo al triple no avisa', () {
      // Es lo que hace un tramo de ripio, un bache largo o una carga pesada:
      // multiplica la vibración entera. Con la energía, esto eran ocho bandas
      // «anómalas» a la vez.
      final base = lineaBase(historia);
      for (final factor in [0.3, 2.0, 3.0, 10.0]) {
        expect(
          compararViaje(
            viaje(15, bandas: [for (final x in normal()) x * factor]),
            base,
          ),
          isEmpty,
          reason: 'todo multiplicado por $factor es un camino, no una falla',
        );
      }
    });

    test('pero la misma banda subiendo SE VE aunque el camino empeore', () {
      final base = lineaBase(historia);
      final maloYAspero = [
        for (var b = 0; b < cantidadDeBandas; b++) (b == 5 ? 0.35 : 0.10) * 3,
      ];
      final desvios = compararViaje(viaje(15, bandas: maloYAspero), base);
      expect(desvios, isNotEmpty);
      expect(desvios.first.banda, 5);
      expect(desvios.map((d) => d.banda).toSet(), {5});
    });

    test('una ventana sin energia no rompe, no cuenta, y no inventa nada', () {
      final base = lineaBase(historia);
      final vacio = viaje(15, bandas: List.filled(8, 0.0), ruido: 0);
      expect(compararViaje(vacio, base), isEmpty);
      expect(lineaBase({1: vacio}), isEmpty);
    });

    test('un tramo corto en esa cubeta no alcanza para decir nada', () {
      final base = lineaBase(historia);
      final malo = normal()..[5] = 0.35;
      expect(compararViaje(viaje(3, bandas: malo), base), isEmpty);
    });

    test('sin linea base suficiente no se compara contra nada', () {
      final base = lineaBase({1: viaje(10)});
      final malo = normal()..[5] = 0.35;
      expect(compararViaje(viaje(15, bandas: malo), base), isEmpty);
    });
  });

  group('la histeresis', () {
    Map<int, List<VentanaVibracion>> conHistoria({
      required int viajesMalos,
      List<double>? malo,
    }) {
      final h = <int, List<VentanaVibracion>>{};
      for (var i = 1; i <= 6; i++) {
        h[i] = viaje(15, semilla: i * 17);
      }
      // Los viajes 7, 8 y 9 son los más nuevos.
      for (var i = 7; i <= 9; i++) {
        final esMalo = i > 9 - viajesMalos;
        h[i] = viaje(
          15,
          bandas: esMalo ? (malo ?? (normal()..[5] = 0.35)) : normal(),
          semilla: i * 17,
        );
      }
      return h;
    }

    final ultimos = [9, 8, 7, 6, 5, 4, 3, 2, 1];

    test('un solo viaje raro no se avisa', () {
      expect(anomalias(conHistoria(viajesMalos: 1), ultimos), isEmpty);
    });

    test('dos seguidos tampoco: el umbral son tres', () {
      expect(anomalias(conHistoria(viajesMalos: 2), ultimos), isEmpty);
    });

    test('tres viajes seguidos con lo mismo, eso si se avisa', () {
      final a = anomalias(conHistoria(viajesMalos: 3), ultimos);
      expect(a, isNotEmpty);
      expect(a.first.banda, 5);
      expect(a.first.cubeta, 4);
      expect(a.first.viajes, 3);
      expect(a.first.z, greaterThan(umbralDeDesvio));
    });

    test('con menos de tres viajes en la historia no se dice nada', () {
      expect(anomalias(conHistoria(viajesMalos: 3), [9, 8]), isEmpty);
    });

    test('el numero que se muestra es el mas chico de los tres', () {
      final h = conHistoria(viajesMalos: 3);
      final base = lineaBase(h, excepto: {9, 8, 7});
      final zs = [
        for (final id in [9, 8, 7])
          compararViaje(h[id]!, base).firstWhere((d) => d.banda == 5).z,
      ];
      final a = anomalias(h, ultimos).first;
      expect(a.z, closeTo(zs.reduce(math.min), 1e-9));
    });
  });
}
