import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/audio/compuerta.dart';
import 'package:sitd_hilux/features/audio/regimen.dart';
import 'package:sitd_hilux/features/audio/registro_audio.dart';
import 'package:sitd_hilux/features/audio/servicio_audio.dart';
import 'package:sitd_hilux/features/motor/detector_motor.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';

/// El banco de la etapa E y del detector del motor (`sitd-37`).
///
/// El motor de las pruebas es SINTÉTICO y se arma como suena un diésel de
/// cuatro cilindros: la fundamental del encendido en RPM/30 Hz y sus
/// armónicos, cada vez más débiles, con ruido de ruta encima. Si el estimador
/// no saca las RPM de ESTO, no las va a sacar de la camioneta.
///
/// **Y eso no alcanzaba** (`sitd-38`): ese motor sintético no tenía la
/// vuelta del cigüeñal (los órdenes ½, 1½, 2½) ni el retumbo de la ruta, y la
/// camioneta sí. Con él todo daba verde y en el viaje 19 las RPM salieron a
/// la mitad. `diesel` los tiene, y reproduce el error de antes.
List<int> motorSintetico(
  double rpm, {
  double ruido = 0.05,
  int semilla = 1,
  double volumen = 0.3,
}) {
  final f0 = rpm / 30;
  final azar = math.Random(semilla);
  return List<int>.generate(hzAudio, (i) {
    final t = i / hzAudio;
    var x = 0.0;
    for (var h = 1; h <= 8; h++) {
      x += math.sin(2 * math.pi * h * f0 * t + h) / h;
    }
    x = volumen * x / 2 + ruido * (azar.nextDouble() * 2 - 1);
    return (x * 32767).round().clamp(-32768, 32767);
  });
}

/// Un diésel como suena en la cabina (`sitd-38`): el encendido y sus
/// armónicos, la vuelta del cigüeñal (órdenes ½, 1½ y 2½ del encendido), y
/// el retumbo de la ruta, un ruido que crece hacia los graves. Con esto el
/// estimador de `sitd-37` leía la MITAD: 851 para 1.700, 1.155 para 2.300 —
/// lo mismo que la camioneta a 110 km/h.
List<int> diesel(
  double rpm, {
  int semilla = 1,
  double ciguenal = 1,
  double retumbo = 0.6,
  double volumen = 0.15,
}) {
  final f = rpm / 30;
  final azar = math.Random(semilla);
  var marron = 0.0;
  return List<int>.generate(hzAudio, (i) {
    final t = i / hzAudio;
    var x = 0.0;
    for (var h = 1; h <= 8; h++) {
      x += math.sin(2 * math.pi * h * f * t + h) / (h * h);
    }
    for (final h in [0.5, 1.5, 2.5]) {
      x +=
          ciguenal *
          math.sin(2 * math.pi * h * f * t + 3 * h) /
          (h * h * 2 + 0.5);
    }
    marron = 0.995 * marron + (azar.nextDouble() * 2 - 1) * 0.05;
    x = volumen * x + retumbo * marron + 0.05 * (azar.nextDouble() * 2 - 1);
    return (x * 16384).round().clamp(-32768, 32767);
  });
}

/// Ruido de ruta solo, sin motor.
List<int> retumbo(int semilla) {
  final azar = math.Random(semilla);
  var m = 0.0;
  return List<int>.generate(hzAudio, (_) {
    m = 0.995 * m + (azar.nextDouble() * 2 - 1) * 0.05;
    return ((0.6 * m + 0.05 * (azar.nextDouble() * 2 - 1)) * 16000).round();
  });
}

void main() {
  group('las RPM con la velocidad del GPS (sitd-38)', () {
    test('las marchas: rpm por km/h de la R150F con diferencial 3,583', () {
      // Los números que cerraron 215 de 251 lecturas del viaje 19, a mano.
      final esperado = [95.8, 51.6, 35.9, 25.0, 21.0];
      for (var g = 1; g <= 5; g++) {
        expect(rpmPorKmh(g), closeTo(esperado[g - 1], 0.1), reason: '$g.ª');
      }
    });

    for (final (marcha, kmh) in [
      (5, 110.0),
      (5, 52.0),
      (4, 60.0),
      (3, 50.0),
      (2, 40.0),
      (4, 100.0),
    ]) {
      final rpm = kmh * rpmPorKmh(marcha);
      for (final semilla in [1, 2, 3]) {
        test(
          '$marcha.ª a ${kmh.round()} km/h (${rpm.round()} RPM), semilla $semilla',
          () {
            final l = leerMotor(diesel(rpm, semilla: semilla), kmh: kmh);
            expect(l.marcha, marcha, reason: 'por marcha ${l.porMarcha}');
            expect(
              (l.rpm! - rpm).abs() / rpm,
              lessThan(0.02),
              reason: 'leyó ${l.rpm}',
            );
          },
        );
      }
    }

    test('el error de octava del viaje 19 ya no pasa, ni sin velocidad', () {
      for (final rpm in [2300.0, 2900.0]) {
        for (final semilla in [1, 2, 3]) {
          final l = leerMotor(diesel(rpm, semilla: semilla));
          expect(l.rpm, isNotNull);
          expect(
            (l.rpm! - rpm).abs() / rpm,
            lessThan(0.02),
            reason: 'leyó ${l.rpm}',
          );
        }
      }
    });

    test('ruido de ruta solo: ninguna marcha, ni RPM libres', () {
      for (var s = 0; s < 10; s++) {
        final l = leerMotor(retumbo(s), kmh: 80);
        expect(l.rpm, isNull, reason: 'por marcha ${l.porMarcha}');
        expect(l.marcha, isNull);
      }
    });

    test('con el embrague apretado (motor a ralentí andando a 80) no inventa marcha', () {
      final l = leerMotor(diesel(780), kmh: 80);
      expect(l.marcha, isNull, reason: 'por marcha ${l.porMarcha}');
    });

    test('no prueba marchas imposibles, y deja picos para el diagnóstico', () {
      final l = leerMotor(diesel(2300), kmh: 110);
      // A 110, 1.ª y 2.ª pedirían más de 4.300 RPM.
      expect(l.porMarcha[0], isNull);
      expect(l.porMarcha[1], isNull);
      expect(l.picos.length, 12);
      // El pico más saliente es el encendido o su doble.
      final f = l.picos.first;
      expect(
        [76.7, 153.3].any((x) => (f - x).abs() < 2),
        isTrue,
        reason: '${l.picos}',
      );
    });
  });

  group('las RPM por el micrófono', () {
    for (final rpm in [750.0, 1200.0, 1800.0, 2600.0, 3800.0]) {
      test('un motor a ${rpm.round()} RPM se lee dentro del 2 %', () {
        final l = leerMotor(motorSintetico(rpm));
        expect(l.rpm, isNotNull, reason: 'prominencia ${l.prominenciaDb} dB');
        expect(
          (l.rpm! - rpm).abs() / rpm,
          lessThan(0.02),
          reason: 'leyó ${l.rpm}',
        );
        expect(l.prominenciaDb, greaterThan(prominenciaMinimaDb));
      });
    }

    test('ruido solo: no inventa RPM', () {
      final azar = math.Random(7);
      final pcm = List<int>.generate(
        hzAudio,
        (_) => ((azar.nextDouble() * 2 - 1) * 6000).round(),
      );
      expect(leerMotor(pcm).rpm, isNull);
    });

    test(
      'un zumbido suelto de 50 Hz (sin armónicos) no gana a un motor más débil',
      () {
        final motor = motorSintetico(1500, volumen: 0.15);
        final pcm = [
          for (var i = 0; i < hzAudio; i++)
            (motor[i] + 0.25 * 32767 * math.sin(2 * math.pi * 50 * i / hzAudio))
                .round()
                .clamp(-32768, 32767),
        ];
        final l = leerMotor(pcm);
        expect(l.rpm, isNotNull);
        expect((l.rpm! - 1500).abs(), lessThan(45), reason: 'leyó ${l.rpm}');
      },
    );

    test('nivel, saturación y bandas', () {
      final silencio = leerMotor(List<int>.filled(hzAudio, 0));
      expect(silencio.nivelDb, -90);
      expect(silencio.rpm, isNull);
      final saturado = leerMotor(
        List<int>.generate(hzAudio, (i) => i.isEven ? 32767 : -32768),
      );
      expect(saturado.saturadas, greaterThan(saturacionMaxima));
      final l = leerMotor(motorSintetico(1800));
      expect(l.bandas.length, bandasDeAudio);
      expect(bordesAudioHz.length, bandasDeAudio + 1);
      // A 1800 RPM el encendido son 60 Hz: la banda de 40-80 Hz manda.
      final mayor = l.bandas.indexOf(l.bandas.reduce(math.max));
      expect(mayor, 1);
    });

    test('un trozo corto no rompe', () {
      expect(leerMotor(List<int>.filled(10, 0)).rpm, isNull);
    });
  });

  group('la compuerta', () {
    MotivoAudio c({
      bool musica = false,
      bool llamada = false,
      double? kmh = 60,
      double? antes = 61,
      double db = -30,
      double sat = 0,
    }) => compuerta(
      musica: musica,
      llamada: llamada,
      kmh: kmh,
      kmhAlEmpezar: antes,
      nivelDb: db,
      saturadas: sat,
    );

    test('abre sólo con todo en orden', () => expect(c(), MotivoAudio.abre));
    test(
      'la llamada manda sobre todo',
      () => expect(
        c(llamada: true, musica: true, kmh: null),
        MotivoAudio.llamada,
      ),
    );
    test(
      'con música no escucha',
      () => expect(c(musica: true), MotivoAudio.musica),
    );
    test('sin velocidad no escucha', () {
      expect(c(kmh: null), MotivoAudio.sinVelocidad);
      expect(c(antes: null), MotivoAudio.sinVelocidad);
    });
    test('despacio no escucha (ni al empezar ni al terminar)', () {
      expect(c(kmh: 29, antes: 29), MotivoAudio.despacio);
      expect(c(kmh: 40, antes: 25), MotivoAudio.despacio);
    });
    test(
      'velocidad que cambia no escucha',
      () => expect(c(kmh: 70, antes: 60), MotivoAudio.inestable),
    );
    test('silencio y saturación', () {
      expect(c(db: -80), MotivoAudio.silencio);
      expect(c(sat: 0.05), MotivoAudio.saturado);
    });
  });

  group('el detector del motor', () {
    test('cerrar a mano un viaje del cargador que no anduvo lo descarta', () {
      final d = DetectorMotor();
      d.abrioElMotor(0);
      expect(d.descartaAlCerrarAMano(1), isTrue, reason: 'el viaje 19: 1 m');
      expect(d.descartaAlCerrarAMano(199), isTrue);
      // Ya anduvo: es un viaje de verdad, aunque después pare.
      d.alLatir(hayViaje: true, t: 60000, metros: 250);
      expect(d.descartaAlCerrarAMano(250), isFalse);
      expect(d.descartaAlCerrarAMano(0), isFalse);
      // Uno que abrió una persona no se descarta nunca.
      final e = DetectorMotor();
      expect(e.descartaAlCerrarAMano(0), isFalse);
    });

    test('al abrir con el cargador puesto NO inventa un viaje', () {
      final d = DetectorMotor();
      expect(
        d.alCambiar(conectado: true, inicial: true, hayViaje: false, t: 0),
        AccionMotor.nada,
      );
    });

    test('pasar a cargar empieza; si ya hay viaje, no hace nada', () {
      final d = DetectorMotor();
      d.alCambiar(conectado: false, inicial: true, hayViaje: false, t: 0);
      expect(
        d.alCambiar(conectado: true, inicial: false, hayViaje: false, t: 1),
        AccionMotor.empezar,
      );
      final e = DetectorMotor();
      e.alCambiar(conectado: false, inicial: true, hayViaje: true, t: 0);
      expect(
        e.alCambiar(conectado: true, inicial: false, hayViaje: true, t: 1),
        AccionMotor.nada,
      );
    });

    test(
      'desenchufado cierra después de la gracia, y sólo lo que abrió el motor',
      () {
        final d = DetectorMotor(gracia: const Duration(minutes: 3));
        d.alCambiar(conectado: true, inicial: true, hayViaje: true, t: 0);
        d.abiertoPorElMotor = true;
        d.alCambiar(conectado: false, inicial: false, hayViaje: true, t: 1000);
        expect(d.alLatir(hayViaje: true, t: 1000 + 179000), AccionMotor.nada);
        expect(d.segundosParaCerrar(1000 + 179000), 1);
        expect(
          d.alLatir(hayViaje: true, t: 1000 + 180000),
          AccionMotor.terminar,
        );
        expect(
          d.alLatir(hayViaje: true, t: 1000 + 200000),
          AccionMotor.nada,
          reason: 'una sola vez',
        );

        final manual = DetectorMotor();
        manual.alCambiar(conectado: true, inicial: true, hayViaje: true, t: 0);
        manual.alCambiar(
          conectado: false,
          inicial: false,
          hayViaje: true,
          t: 0,
        );
        expect(
          manual.alLatir(hayViaje: true, t: 999999),
          AccionMotor.nada,
          reason: 'lo abrió una persona',
        );
      },
    );

    test(
      'cargador de la casa (sitd-40): a los 5 min sin moverse, se descarta',
      () {
        final d = DetectorMotor();
        d.alCambiar(conectado: false, inicial: true, hayViaje: false, t: 0);
        d.alCambiar(conectado: true, inicial: false, hayViaje: false, t: 0);
        d.abrioElMotor(0);
        expect(d.aPrueba, isTrue);
        expect(
          d.alLatir(hayViaje: true, t: 299000, metros: 30),
          AccionMotor.nada,
        );
        expect(
          d.alLatir(hayViaje: true, t: 300000, metros: 30),
          AccionMotor.descartar,
        );
        expect(
          d.alLatir(hayViaje: true, t: 301000, metros: 30),
          AccionMotor.nada,
          reason: 'una sola vez',
        );
      },
    );

    test(
      'si la camioneta anduvo, es un viaje: no se descarta y se cierra normal',
      () {
        final d = DetectorMotor();
        d.alCambiar(conectado: false, inicial: true, hayViaje: false, t: 0);
        d.alCambiar(conectado: true, inicial: false, hayViaje: false, t: 0);
        d.abrioElMotor(0);
        expect(
          d.alLatir(hayViaje: true, t: 60000, metros: 250),
          AccionMotor.nada,
        );
        expect(d.aPrueba, isFalse);
        // Una parada larga en el camino (metros quietos) ya no lo descarta.
        expect(
          d.alLatir(hayViaje: true, t: 900000, metros: 250),
          AccionMotor.nada,
        );
        d.alCambiar(
          conectado: false,
          inicial: false,
          hayViaje: true,
          t: 900000,
        );
        expect(
          d.alLatir(hayViaje: true, t: 1080000, metros: 250),
          AccionMotor.terminar,
        );
      },
    );

    test('se desenchufa antes de andar: se descarta en vez de guardarse', () {
      final d = DetectorMotor();
      d.alCambiar(conectado: false, inicial: true, hayViaje: false, t: 0);
      d.alCambiar(conectado: true, inicial: false, hayViaje: false, t: 0);
      d.abrioElMotor(0);
      d.alCambiar(conectado: false, inicial: false, hayViaje: true, t: 60000);
      expect(
        d.alLatir(hayViaje: true, t: 60000 + 180000, metros: 0),
        AccionMotor.descartar,
      );
    });

    test('un viaje que abrió una persona nunca se descarta', () {
      final d = DetectorMotor();
      d.alCambiar(conectado: true, inicial: true, hayViaje: true, t: 0);
      expect(
        d.alLatir(hayViaje: true, t: 9999999, metros: 0),
        AccionMotor.nada,
      );
    });

    test('si vuelve la carga antes de la gracia, no pasó nada', () {
      final d = DetectorMotor();
      d.alCambiar(conectado: true, inicial: true, hayViaje: true, t: 0);
      d.abiertoPorElMotor = true;
      d.alCambiar(conectado: false, inicial: false, hayViaje: true, t: 0);
      d.alCambiar(conectado: true, inicial: false, hayViaje: true, t: 60000);
      expect(d.alLatir(hayViaje: true, t: 400000), AccionMotor.nada);
      expect(d.segundosParaCerrar(400000), isNull);
    });
  });

  group('el servicio del micrófono', () {
    late Base base;
    late RegistroDeAudio registro;
    late int viaje;

    setUp(() {
      base = Base.abrir(':memory:');
      registro = RegistroDeAudio(base);
      viaje = RegistroDeViajes(base).abrir(inicio: 1);
    });
    tearDown(() => base.cerrar());

    test(
      'guarda una de cada cinco ventanas, y sólo las que pasan la compuerta',
      () async {
        final trozos = StreamController<List<int>>();
        var kmh = 60.0;
        var musica = false;
        final s = ServicioAudio(
          registro: registro,
          abrir: () => trozos.stream,
          ocupado: () async => (musica: musica, llamada: false),
          velocidadKmh: () => kmh,
          reloj: () => 5,
        );
        s.arrancar(viaje);
        for (var i = 0; i < 10; i++) {
          trozos.add(motorSintetico(1800, semilla: i));
          await Future<void>.delayed(Duration.zero);
        }
        // Trozos 1 y 6 se procesan; el 1 no tiene «velocidad al empezar».
        expect(s.guardadas, 1);
        expect(s.descartes[MotivoAudio.sinVelocidad], 1);
        final v = registro.deViaje(viaje).single;
        expect((v.rpm! - 1800).abs(), lessThan(36));
        expect(v.hz, hzAudio);

        musica = true;
        for (var i = 0; i < 5; i++) {
          trozos.add(motorSintetico(1800, semilla: i));
          await Future<void>.delayed(Duration.zero);
        }
        expect(s.descartes[MotivoAudio.musica], 1);
        kmh = 10;
        await s.detener();
        expect(s.escuchando, isFalse);
        await trozos.close();
      },
    );

    test('el tacómetro escucha TODOS los segundos, aunque se guarde uno de cada cinco (sitd-39)', () async {
      final trozos = StreamController<List<int>>();
      var t = 0;
      final s = ServicioAudio(
        registro: registro,
        abrir: () => trozos.stream,
        ocupado: () async => (musica: false, llamada: false),
        velocidadKmh: () => 50,
        reloj: () => t,
      );
      s.arrancar(viaje);
      final rpm = 50 * rpmPorKmh(3);
      for (var i = 0; i < 4; i++) {
        t = i * 1000;
        trozos.add(motorSintetico(rpm, semilla: i));
        await Future<void>.delayed(Duration.zero);
      }
      // Se guardó a lo sumo uno, pero la marcha ya está tomada y las RPM
      // salen del GPS.
      expect(s.guardadas, lessThanOrEqualTo(1));
      expect(s.tacometro.marcha, 3);
      expect(s.tacometro.leer(4000, 52)!.rpm, closeTo(52 * rpmPorKmh(3), 0.01));
      await s.detener();
      await trozos.close();
    });

    test('un canal que no contesta cuenta como «no escuchar»', () async {
      final trozos = StreamController<List<int>>();
      final s = ServicioAudio(
        registro: registro,
        abrir: () => trozos.stream,
        ocupado: () async => throw Exception('sin canal'),
        velocidadKmh: () => 60,
        cadaCuantos: 1,
      );
      s.arrancar(viaje);
      trozos.add(motorSintetico(1800));
      trozos.add(motorSintetico(1800));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(s.guardadas, 0);
      await s.detener();
      await trozos.close();
    });

    test('no guarda una sola muestra de audio: sólo números', () {
      final columnas = base.db
          .select('PRAGMA table_info(audio)')
          .map((f) => f['name'] as String)
          .toSet();
      expect(columnas, {
        'id',
        'viaje',
        't',
        'kmh',
        'rpm',
        'prominencia',
        'nivel',
        'hz',
        'bandas',
        // sitd-38: cinco números y doce números. Tampoco es sonido.
        'marcha',
        'marchas',
        'picos',
      });
    });

    test('borrar un viaje se lleva su audio (sitd-40, ON DELETE CASCADE)', () {
      registro.guardar(
        viaje,
        VentanaAudio.de(
          leerMotor(motorSintetico(1800), kmh: 50),
          t: 1,
          kmh: 50,
        ),
      );
      expect(registro.deViaje(viaje), isNotEmpty);
      RegistroDeViajes(base).borrar(viaje);
      expect(registro.deViaje(viaje), isEmpty);
      expect(RegistroDeViajes(base).porId(viaje), isNull);
    });

    test('la marcha y el diagnóstico van y vuelven de la base (sitd-38)', () {
      final v = RegistroDeViajes(base).abrir(inicio: 1000);
      final l = leerMotor(diesel(2300), kmh: 110);
      final r = RegistroDeAudio(base)
        ..guardar(v, VentanaAudio.de(l, t: 2000, kmh: 110));
      final w = r.deViaje(v).single;
      expect(w.marcha, 5);
      expect(w.porMarcha.length, 5);
      expect(w.porMarcha[0], isNull);
      expect(w.porMarcha[4], closeTo(l.porMarcha[4]!, 0.05));
      expect(w.picos, l.picos);
      expect(w.picos.length, lessThanOrEqualTo(12));
      final m = w.aMapa();
      expect(m['marcha'], 5);
      expect((m['marchas'] as List).first, isNull);
    });
  });
}
