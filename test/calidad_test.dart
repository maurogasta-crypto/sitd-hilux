import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/vibracion/calidad.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/vibracion/registro_pruebas.dart';
import 'package:sitd_hilux/features/vibracion/sacudon.dart';

/// Un sensor de mentira que entrega exactamente cuando tiene que entregar.
///
/// [hz] es la frecuencia de muestreo; [señalHz] la vibración que se le pone
/// adentro. Con `jitterRelativo` se le mete irregularidad, y con `perder` se
/// le tiran muestras: las dos cosas que este banco tiene que poder distinguir.
List<Sacudon> sensorFalso({
  required double hz,
  double senalHz = 10,
  double amplitud = 1,
  int cuantas = 512,
  double jitterRelativo = 0,
  int perderCada = 0,
  double tope = double.infinity,
  int semilla = 3,
}) {
  final r = math.Random(semilla);
  final paso = 1e6 / hz; // microsegundos
  final salida = <Sacudon>[];
  var u = 1758400000000000.0;
  for (var i = 0; i < cuantas; i++) {
    u += paso * (1 + (r.nextDouble() - 0.5) * 2 * jitterRelativo);
    if (perderCada > 0 && i % perderCada == perderCada - 1) continue;
    final t = (u - 1758400000000000.0) / 1e6;
    // 9,8 es la gravedad: el módulo de un acelerómetro quieto no es cero.
    var v = 9.8 + amplitud * math.sin(2 * math.pi * senalHz * t);
    if (v > tope) v = tope;
    salida.add(Sacudon((u ~/ 1000), v, micros: u.round()));
  }
  return salida;
}

void main() {
  group('la frecuencia y la regularidad', () {
    test('un metrónomo a 50 Hz se mide como 50 Hz y sin jitter', () {
      final c = medirCalidad(sensorFalso(hz: 50));
      expect(c.sirve, isTrue);
      expect(c.hz, closeTo(50, 0.1));
      expect(c.nyquist, closeTo(25, 0.05));
      expect(c.irregularidad, closeTo(0, 0.01));
      expect(c.huecos, 0);
    });

    test('y a 400 Hz también, que es lo que hay que poder medir', () {
      /* Es el modo `fastest`: el experimento entero es averiguar qué entrega
         un teléfono cuando se le pide todo. */
      final c = medirCalidad(sensorFalso(hz: 400, senalHz: 60, cuantas: 2048));
      expect(c.hz, closeTo(400, 1));
      expect(c.rpmMaximoVisible, closeTo(6000, 20));
    });

    test(
      'LOS MICROSEGUNDOS NO SON UN LUJO: en milisegundos, 400 Hz miente',
      () {
        /* Es el motivo por el que `Sacudon` lleva `tMicro`. A 400 Hz el
         intervalo es de 2,5 ms; un sello redondeado al milisegundo lo convierte
         en 2 o en 3, y el instrumento reportaría un 50 % de irregularidad que
         NO EXISTE — estaría midiendo su propia regla y no el sensor.

         Acá se compara la misma tanda perfecta, medida de las dos formas. */
        final buenas = sensorFalso(hz: 400, cuantas: 1024);
        final conReglaGruesa = [
          for (final s in buenas) Sacudon(s.t, s.magnitud), // micros = t * 1000
        ];

        final fina = medirCalidad(buenas);
        final gruesa = medirCalidad(conReglaGruesa);

        expect(
          fina.irregularidad,
          closeTo(0, 0.05),
          reason: 'la tanda es perfecta',
        );
        expect(
          gruesa.irregularidad,
          greaterThan(0.3),
          reason: 'con el sello al milisegundo tenía que verse irregular',
        );
      },
    );

    test('la irregularidad de verdad se mide', () {
      final c = medirCalidad(sensorFalso(hz: 50, jitterRelativo: 0.6));
      expect(c.irregularidad, greaterThan(0.8));
      expect(medirCalidad(sensorFalso(hz: 50)).irregularidad, lessThan(0.05));
    });

    test('una muestra que FALTA se cuenta como hueco, no como jitter', () {
      /* Son dos problemas distintos y se arreglan distinto: el jitter es el
         sistema entregando tarde, un hueco es el sistema no entregando. */
      final c = medirCalidad(sensorFalso(hz: 50, perderCada: 20));
      expect(c.huecos, greaterThan(10));
    });

    test('con pocas muestras no se inventa un número: se dice', () {
      final c = medirCalidad(sensorFalso(hz: 50, cuantas: 40));
      expect(c.sirve, isFalse);
      expect(c.problema, contains('suficientes'));
    });

    test('sellos repetidos o al revés son un problema, no un cero', () {
      /* Un cero de frecuencia se vería igual que «el sensor no entrega», y son
         cosas opuestas: acá el sensor entrega y el que está roto es el reloj. */
      final s = sensorFalso(hz: 50);
      final rotas = [...s];
      rotas[80] = Sacudon(
        rotas[10].t,
        rotas[80].magnitud,
        micros: rotas[10].tMicro,
      );
      final c = medirCalidad(rotas);
      expect(c.sirve, isFalse);
      expect(c.problema, contains('sellos de tiempo'));
    });
  });

  group('el espectro', () {
    test('encuentra el pico donde está la vibración', () {
      final c = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12, amplitud: 2, cuantas: 1024),
      );
      expect(c.picoHz, closeTo(12, 0.6));
    });

    test('una vibración clara es NÍTIDA y el ruido no', () {
      /* `nitidez` es el número con el que se comparan dos soportes, así que
         tiene que separar «se ve algo» de «hay energía». */
      final claro = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12, amplitud: 2, cuantas: 1024),
      );
      final r = math.Random(9);
      final ruido = <Sacudon>[];
      for (var i = 0; i < 1024; i++) {
        final u = 1758400000000000 + i * 10000;
        ruido.add(
          Sacudon(u ~/ 1000, 9.8 + (r.nextDouble() - 0.5) * 4, micros: u),
        );
      }
      final sucio = medirCalidad(ruido);

      expect(claro.nitidez, greaterThan(8));
      expect(sucio.nitidez, lessThan(claro.nitidez / 2));
    });

    test('la saturación se cuenta, porque recortar inventa armónicos', () {
      /* Y una senoidal LIMPIA no cuenta como saturada aunque pase mucho
         tiempo cerca de su pico: lo que delata al recorte son los valores
         idénticos repetidos, no la cercanía al máximo. El primer intento
         contaba por cercanía y le daba un 6 % de saturación a una señal
         perfecta. */
      final c = medirCalidad(
        sensorFalso(
          hz: 100,
          senalHz: 12.3,
          amplitud: 4,
          tope: 11.5,
          cuantas: 1024,
        ),
      );
      expect(c.saturadas, greaterThan(20));
      final sano = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12.3, amplitud: 1, cuantas: 1024),
      );
      expect(sano.saturadas, lessThan(5));
    });

    test('la gravedad no se cuela en el pico', () {
      /* El módulo de un acelerómetro quieto vale 9,8: si no se le sacara la
         media, el pico dominante de cualquier medición sería la continua y
         esta pantalla no diría nada nunca. */
      final c = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12, amplitud: 0.5, cuantas: 1024),
      );
      expect(c.picoHz, greaterThan(2));
      expect(c.picoHz, closeTo(12, 1));
    });
  });

  group('lo que se puede ver, dicho en RPM y en km/h', () {
    test('a 50 Hz el motor NO se ve, ni el ralentí', () {
      /* Es el hallazgo del 2026-09-22 y el motivo de toda esta pantalla. El
         encendido de un 4 cilindros de 4 tiempos es RPM/30: a 50 Hz de
         muestreo el techo son 747 RPM, y el ralentí de un 1KD ya está arriba. */
      final c = medirCalidad(sensorFalso(hz: 49.85, cuantas: 1024));
      expect(c.rpmMaximoVisible, lessThan(800));
      expect(
        c.laRuedaSeVe,
        isTrue,
        reason: 'la rueda sí entra, y es lo que hay',
      );

      final dicho = leerCalidad(c);
      expect(
        dicho.any(
          (h) => h.grado == Grado.malo && h.texto.contains('tacómetro'),
        ),
        isTrue,
      );
    });

    test('a 200 Hz el tacómetro sale del acelerómetro solo', () {
      final c = medirCalidad(sensorFalso(hz: 200, senalHz: 40, cuantas: 2048));
      expect(c.rpmMaximoVisible, greaterThan(2900));
      final dicho = leerCalidad(c);
      expect(
        dicho.any(
          (h) => h.grado == Grado.bueno && h.texto.contains('sin micrófono'),
        ),
        isTrue,
      );
    });

    test('a 20 Hz se pierde hasta la rueda, y lo dice', () {
      final c = medirCalidad(sensorFalso(hz: 20, senalHz: 5, cuantas: 512));
      expect(c.laRuedaSeVe, isFalse);
      expect(
        leerCalidad(c).any((h) => h.texto.contains('NO se ve entera')),
        isTrue,
      );
    });

    test('con velocidad, dice DÓNDE habría que mirar', () {
      final c = medirCalidad(sensorFalso(hz: 100, cuantas: 1024));
      final dicho = leerCalidad(c, velocidadKmh: 80);
      final cruce = dicho.firstWhere((h) => h.grado == Grado.dato);
      // 80 km/h con rueda de 76 cm: 9,31 Hz.
      expect(cruce.texto, contains('9,3'.replaceAll(',', '.')));
    });

    test('quieto no inventa el cruce con la velocidad', () {
      final c = medirCalidad(sensorFalso(hz: 100, cuantas: 1024));
      expect(leerCalidad(c).any((h) => h.grado == Grado.dato), isFalse);
    });

    test('una medición que no sirve dice UNA cosa y no cinco', () {
      final c = medirCalidad(sensorFalso(hz: 50, cuantas: 10));
      final dicho = leerCalidad(c);
      expect(dicho, hasLength(1));
      expect(dicho.single.grado, Grado.malo);
    });
  });

  group('el resumen', () {
    test('entra en un renglón y trae los cuatro números que importan', () {
      final c = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12, amplitud: 2, cuantas: 1024),
      );
      expect(c.resumen, contains('Hz'));
      expect(c.resumen, contains('Nyquist'));
      expect(c.resumen, contains('irregularidad'));
      expect(c.resumen, contains('nitidez'));
      expect(c.resumen.length, lessThan(110));
    });
  });

  group('las pruebas guardadas', () {
    late Base base;
    setUp(() => base = Base.abrir(':memory:'));
    tearDown(() => base.cerrar());

    test('lo que se guarda vuelve igual', () {
      /* Los dos percentiles del intervalo no se guardan sueltos: se guarda la
         irregularidad, que es lo que se compara. Al releer se rearman de modo
         que el número vuelva a dar lo mismo — si alguien toca esa cuenta, esto
         falla acá y no seis meses después mirando una lista con números que no
         cierran. */
      final c = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12.3, amplitud: 2, cuantas: 1024),
      );
      final r = RegistroDePruebas(base);
      r.guardar(
        PruebaDeSensor(
          t: 1758500000000,
          soporte: 'palanca de cambios',
          periodoMs: 20,
          situacion: 'ralentí',
          calidad: c,
        ),
      );

      final leida = r.ultimas().single;
      expect(leida.soporte, 'palanca de cambios');
      expect(leida.situacion, 'ralentí');
      expect(leida.calidad.hz, closeTo(c.hz, 1e-6));
      expect(leida.calidad.irregularidad, closeTo(c.irregularidad, 1e-6));
      expect(leida.calidad.nitidez, closeTo(c.nitidez, 1e-6));
      expect(leida.calidad.picoHz, closeTo(c.picoHz, 1e-6));
      expect(leida.calidad.rpmMaximoVisible, closeTo(c.rpmMaximoVisible, 1e-6));
    });

    test('sólo se comparan las que midieron LO MISMO', () {
      /* Es la misma regla que las cubetas de velocidad: un soporte que parece
         mejor puede ser simplemente el que se probó con el motor en marcha. */
      final r = RegistroDePruebas(base);
      final floja = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12.3, amplitud: 0.05, cuantas: 1024),
      );
      final clara = medirCalidad(
        sensorFalso(hz: 100, senalHz: 12.3, amplitud: 3, cuantas: 1024),
      );
      r.guardar(
        PruebaDeSensor(
          t: 1,
          soporte: 'tablero',
          periodoMs: 20,
          situacion: 'ralentí',
          calidad: floja,
        ),
      );
      r.guardar(
        PruebaDeSensor(
          t: 2,
          soporte: 'palanca',
          periodoMs: 20,
          situacion: 'ralentí',
          calidad: clara,
        ),
      );
      r.guardar(
        PruebaDeSensor(
          t: 3,
          soporte: 'piso',
          periodoMs: 20,
          situacion: 'andando a 80',
          calidad: clara,
        ),
      );

      final mismo = r.compararSoportes('ralentí');
      expect(
        mismo.map((p) => p.soporte),
        ['palanca', 'tablero'],
        reason:
            'tiene que venir ordenado por nitidez, y sin el de otra situación',
      );
      expect(r.situaciones(), containsAll(['ralentí', 'andando a 80']));
    });

    test('el período pedido se guarda, porque el medido no lo dice', () {
      final r = RegistroDePruebas(base);
      final c = medirCalidad(sensorFalso(hz: 49.85, cuantas: 1024));
      r.guardar(
        PruebaDeSensor(t: 1, soporte: 'tablero', periodoMs: 20, calidad: c),
      );
      final leida = r.ultimas().single;
      expect(leida.periodoMs, 20);
      expect(leida.comoSePidio, contains('50 Hz pedidos'));
      expect(
        leida.calidad.hz,
        closeTo(49.85, 0.2),
        reason: 'se pidieron 50 y entregó 49,85: ésa es toda la gracia',
      );
    });

    test('«lo más rápido» se dice con palabras, no con un cero', () {
      final r = RegistroDePruebas(base);
      r.guardar(
        PruebaDeSensor(
          t: 1,
          soporte: 'tablero',
          periodoMs: 0,
          calidad: medirCalidad(sensorFalso(hz: 400, cuantas: 2048)),
        ),
      );
      expect(r.ultimas().single.comoSePidio, 'lo más rápido');
    });
  });
}
