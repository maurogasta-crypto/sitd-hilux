import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/nube/recorrido.dart';
import 'package:sitd_hilux/features/odometro/integrador.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';

/// Un viaje de mentira con forma de viaje de verdad: el receptor entrega
/// aproximadamente una vez por segundo pero no exactamente, la camioneta se
/// mueve, y la altitud cambia.
List<Muestra> viajeFalso(int n, {int semilla = 7}) {
  final r = Random(semilla);
  var t = 1758400000000;
  var lat = -34.9011;
  var lon = -56.1645;
  var alt = 412.0;
  return [
    for (var i = 0; i < n; i++)
      () {
        t += 900 + r.nextInt(1600);
        lat += (r.nextDouble() - 0.4) * 0.0004;
        lon += (r.nextDouble() - 0.5) * 0.0004;
        alt += (r.nextDouble() - 0.45) * 1.5;
        return Muestra(
          t: t,
          lat: lat,
          lon: lon,
          alt: alt,
          velocidad: 5 + r.nextDouble() * 25,
          precision: 3.5 + r.nextDouble() * 7,
          precisionVel: 0.1 + r.nextDouble() * 0.5,
        );
      }(),
  ];
}

/// El mismo punto pero sin altitud ni precisión de velocidad, que son las dos
/// columnas que el esquema deja vacías.
Muestra sinRelieve(Muestra m) => Muestra(
  t: m.t,
  lat: m.lat,
  lon: m.lon,
  velocidad: m.velocidad,
  precision: m.precision,
);

void main() {
  group('ida y vuelta', () {
    test('lo que entra es lo que sale, dentro de lo que el sensor sabe', () {
      final antes = viajeFalso(500);
      final despues = decodificarRecorrido(codificarRecorrido(antes));

      expect(despues, hasLength(antes.length));
      for (var i = 0; i < antes.length; i++) {
        final a = antes[i];
        final b = despues[i];
        // El instante NO se redondea: la distancia se integra con `dt`.
        expect(b.t, a.t, reason: 'el punto $i cambió de instante');
        // 1e-6 grados ≈ 11 cm; el redondeo mete a lo sumo la mitad.
        expect((b.lat - a.lat).abs(), lessThan(0.6e-6));
        expect((b.lon - a.lon).abs(), lessThan(0.6e-6));
        expect((b.alt! - a.alt!).abs(), lessThan(0.06));
        expect((b.velocidad - a.velocidad).abs(), lessThan(0.006));
        expect((b.precision - a.precision).abs(), lessThan(0.06));
        expect((b.precisionVel! - a.precisionVel!).abs(), lessThan(0.006));
      }
    });

    test('el error de la posición es MUCHO más chico que el del GPS', () {
      /* Es el permiso para redondear, y es un número y no una impresión: si
         alguien baja una escala y esto empieza a fallar, el redondeo pasó a
         pesar tanto como el sensor. */
      final antes = viajeFalso(800);
      final despues = decodificarRecorrido(codificarRecorrido(antes));
      var peor = 0.0;
      for (var i = 0; i < antes.length; i++) {
        peor = max(peor, (despues[i].lat - antes[i].lat).abs() * 111320);
      }
      final precisionTipica =
          antes.map((m) => m.precision).reduce((a, b) => a + b) / antes.length;
      expect(peor, lessThan(0.1), reason: 'el redondeo mete $peor m');
      expect(peor * 50, lessThan(precisionTipica));
    });

    test('un viaje vacío se codifica y se vuelve a abrir vacío', () {
      expect(decodificarRecorrido(codificarRecorrido([])), isEmpty);
    });

    test('un solo punto también', () {
      final uno = viajeFalso(1);
      final vuelta = decodificarRecorrido(codificarRecorrido(uno));
      expect(vuelta, hasLength(1));
      expect(vuelta.single.t, uno.single.t);
    });
  });

  group('los huecos', () {
    test('una altitud que falta vuelve a faltar, no vuelve en cero', () {
      /* Un cero de altitud es el nivel del mar: si un hueco volviera así, un
         viaje en la sierra tendría una bajada de setecientos metros que nunca
         pasó. */
      final base = viajeFalso(30);
      final con = [
        for (var i = 0; i < base.length; i++)
          i % 7 == 3 ? sinRelieve(base[i]) : base[i],
      ];
      final vuelta = decodificarRecorrido(codificarRecorrido(con));
      for (var i = 0; i < con.length; i++) {
        expect(vuelta[i].alt == null, con[i].alt == null, reason: 'punto $i');
      }
    });

    test('un hueco NO corre la cadena de los que vienen después', () {
      /* Es el error que este formato podría cometer en silencio: si el valor
         que falta moviera el acumulado, todas las altitudes siguientes
         saldrían desplazadas y el perfil del camino sería falso. */
      final base = viajeFalso(40);
      final con = [
        for (var i = 0; i < base.length; i++)
          i == 10 ? sinRelieve(base[i]) : base[i],
      ];
      final vuelta = decodificarRecorrido(codificarRecorrido(con));
      for (var i = 11; i < con.length; i++) {
        expect(
          (vuelta[i].alt! - con[i].alt!).abs(),
          lessThan(0.06),
          reason: 'la altitud del punto $i se corrió por el hueco del 10',
        );
      }
    });

    test('todas las altitudes vacías no rompen nada', () {
      final sinAlt = viajeFalso(20).map(sinRelieve).toList();
      final vuelta = decodificarRecorrido(codificarRecorrido(sinAlt));
      expect(vuelta.every((m) => m.alt == null), isTrue);
      expect(vuelta.every((m) => m.precisionVel == null), isTrue);
    });

    test('sin huecos, el documento no paga por los huecos', () {
      final m = jsonDecode(codificarRecorrido(viajeFalso(10))) as Map;
      expect(m.containsKey('sin_alt'), isFalse);
      expect(m.containsKey('sin_pv'), isFalse);
    });
  });

  group('las dos distancias sobreviven, y son las que mandan', () {
    test('la Doppler no se mueve: el tiempo va exacto', () {
      /* Es LA distancia de este proyecto: velocidad × dt integrado. Si el
         formato la moviera, el recorrido guardado diría otros kilómetros que
         el teléfono, y no habría forma de saber cuál de los dos miente. */
      final antes = viajeFalso(3000);
      final despues = decodificarRecorrido(codificarRecorrido(antes));
      final a = integrar(antes);
      final b = integrar(despues);
      /* El umbral es RELATIVO y no un número de metros, porque el error de
         cuantizar la velocidad es un paseo al azar: cada muestra aporta hasta
         media centésima de m/s por su `dt`, y esos aportes se cancelan entre
         sí, así que cuanto más largo el viaje más metros puede sumar en
         términos absolutos aunque la proporción no se mueva. Un viaje de
         90 km sintéticos da ~0,6 m; el real de 69,8 km dio 0,01 m.

         10 partes por millón deja pasar eso y frena lo que hay que frenar:
         redondear el instante a segundos, o la velocidad a décimas, lo
         multiplican por diez o por cien. */
      expect((b.metros - a.metros).abs() / a.metros, lessThan(1e-5));
      expect(b.msIntegrados, a.msIntegrados);
      expect(b.muestrasUsadas, a.muestrasUsadas);
      expect(b.cortes, a.cortes);
    });

    test('y el haversine de CONTROL sigue sirviendo de control', () {
      /* Es la prueba que decidió la escala de la posición, y por eso está.
         El haversine suma el error de cada punto y nunca lo resta —el mismo
         efecto que hace que no se integre la posición—, así que el redondeo
         se le acumula a lo largo del viaje. Con 1e-5 se corría 73 m en un
         viaje de 70 km: un control que se mueve así deja de controlar. Con
         1e-6 se queda en poco más de un metro.

         Si alguien baja la escala para ahorrar espacio, esto falla acá y no
         seis meses después mirando un número raro. */
      final antes = viajeFalso(3000);
      final despues = decodificarRecorrido(codificarRecorrido(antes));
      final a = integrar(antes).metrosHaversine;
      final b = integrar(despues).metrosHaversine;
      expect(
        (b - a).abs() / a,
        lessThan(0.0002),
        reason:
            'el haversine se corrió ${(b - a).toStringAsFixed(1)} m '
            'sobre ${(a / 1000).toStringAsFixed(1)} km',
      );
    });
  });

  group('el tamaño, que es el motivo del formato', () {
    test('un viaje de 5343 puntos entra en UN documento de Firestore', () {
      /* 5343 es el viaje real del 2026-09-21. El tope de un documento es
         1 MiB y la regla corta en 900 000. */
      final texto = codificarRecorrido(viajeFalso(5343));
      // Sobre el viaje real son 117 KiB: entra con ocho veces de margen.
      expect(
        texto.length,
        lessThan(900000),
        reason: 'no entra: ${texto.length} caracteres',
      );
    });

    test('y ocupa MUCHO menos que una lista por punto', () {
      final puntos = viajeFalso(2000);
      final nuestro = codificarRecorrido(puntos).length;
      final crudo = jsonEncode([
        for (final m in puntos)
          [m.t, m.lat, m.lon, m.alt, m.velocidad, m.precision, m.precisionVel],
      ]).length;
      expect(
        nuestro * 3,
        lessThan(crudo),
        reason: 'sólo ahorra ${(crudo / nuestro).toStringAsFixed(1)}×',
      );
    });
  });

  group('lo que no se puede abrir se DICE, no se abre a medias', () {
    test('un texto que no es JSON', () {
      expect(
        () => decodificarRecorrido('no soy json'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no es JSON'),
          ),
        ),
      );
    });

    test('un JSON que no es un recorrido', () {
      expect(
        () => decodificarRecorrido('{"hola":1}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('una versión MÁS NUEVA no se abre', () {
      /* Misma regla que el esquema de la base: lo que esta compilación no
         conoce se perdería sin aviso. */
      final m =
          jsonDecode(codificarRecorrido(viajeFalso(5))) as Map<String, dynamic>;
      m['v'] = versionDelRecorrido + 1;
      expect(
        () => decodificarRecorrido(jsonEncode(m)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('más nueva'),
          ),
        ),
      );
    });

    test('una columna a la que le faltan valores', () {
      final m = jsonDecode(
        codificarRecorrido(viajeFalso(10)),
      ) as Map<String, dynamic>;
      (m['lat'] as List).removeLast();
      expect(
        () => decodificarRecorrido(jsonEncode(m)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('faltan valores'),
          ),
        ),
      );
    });

    test('una escala que no sirve', () {
      final m = jsonDecode(
        codificarRecorrido(viajeFalso(10)),
      ) as Map<String, dynamic>;
      (m['esc'] as Map)['lat'] = 0;
      expect(
        () => decodificarRecorrido(jsonEncode(m)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('las escalas viajan ADENTRO del documento, no en la constante', () {
    /* Es lo que hace que un recorrido guardado hoy se pueda leer el día que
       estos números cambien. Si alguien las saca del documento para
       «ahorrar», los recorridos viejos se leen mal y en silencio. */
    final m = jsonDecode(codificarRecorrido(viajeFalso(3))) as Map;
    expect(m['esc'], escalasDelRecorrido);

    // Y se usan las del documento: con una escala distinta, el valor cambia.
    final otro = Map<String, dynamic>.from(m);
    otro['esc'] = {...escalasDelRecorrido, 'alt': 1};
    final vuelta = decodificarRecorrido(jsonEncode(otro));
    final normal = decodificarRecorrido(jsonEncode(m));
    expect(vuelta.first.alt, closeTo(normal.first.alt! * 10, 1e-9));
  });
}
