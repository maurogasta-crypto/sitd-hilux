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

void main() {
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
      });
    });
  });
}
