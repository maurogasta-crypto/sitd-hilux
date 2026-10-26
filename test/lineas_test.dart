import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/audio/regimen.dart';
import 'package:sitd_hilux/features/vibracion/lineas.dart';
import 'package:sitd_hilux/features/vibracion/rueda.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';

/// Cinco segundos de acelerómetro a 200 Hz con tonos en [tonos] (Hz →
/// amplitud) y ruido.
List<double> senal(Map<double, double> tonos, {int semilla = 1}) {
  final azar = math.Random(semilla);
  return List<double>.generate(1000, (i) {
    final t = i / 200;
    var x = 9.81 + 0.02 * (azar.nextDouble() * 2 - 1);
    tonos.forEach((f, a) => x += a * math.sin(2 * math.pi * f * t + f));
    return x;
  });
}

VentanaVibracion? ventana(
  Map<double, double> tonos, {
  double kmh = 80,
  int? marcha,
  int semilla = 1,
  int t = 0,
}) => armarVentana(
  magnitud: senal(tonos, semilla: semilla),
  tInicio: t,
  tFin: t + 4995,
  cubeta: cubetaDe(kmh)!,
  kmh: kmh,
  marcha: marcha,
);

/// Una ventana armada a mano con la rueda 2× en [veces] y corrida [corr] %.
VentanaVibracion conLinea(double veces, double corr, {int t = 0}) =>
    VentanaVibracion(
      t: t,
      cubeta: 6,
      hz: 201,
      muestras: 1000,
      rms: 0.5,
      pico: 1,
      bandas: List.filled(8, 0.1),
      lineas: {Linea.r2: MedidaDeLinea(veces, corr)},
    );

void main() {
  setUp(() => usarCircunferenciaMedida(null));

  group('medir las líneas en una ventana (sitd-55)', () {
    test('a 80 km/h, la rueda 2× se ve donde tiene que estar', () {
      final f = Linea.r2.frecuencia(80, null)!;
      final v = ventana({f: 0.05})!;
      final m = v.lineas[Linea.r2]!;
      expect(m.veces, greaterThan(5), reason: 'veces ${m.veces}');
      expect(m.corrimiento.abs(), lessThan(0.6));
      // Sin marcha, las del motor no se miden.
      expect(v.lineas.containsKey(Linea.m1), isFalse);
      expect(v.lineas.containsKey(Linea.c1), isTrue);
    });

    test('una rueda que gira un 2 % más despacio se ve corrida', () {
      final f = Linea.r2.frecuencia(80, null)! * 0.98;
      final m = ventana({f: 0.05})!.lineas[Linea.r2]!;
      expect(m.corrimiento, closeTo(-2, 0.6));
    });

    test('las del motor, con la marcha: el encendido en 5.ª', () {
      final f = Linea.m2.frecuencia(80, 5)!;
      // 80 km/h en 5.ª son unas 1.650 RPM: el encendido, a RPM/30.
      expect(f, closeTo(80 * rpmPorKmh(5) / 30, 0.01));
      final v = ventana({f: 0.05}, marcha: 5)!;
      expect(v.lineas[Linea.m2]!.veces, greaterThan(5));
    });

    test('en 5.ª el motor da justo tres vueltas por vuelta de rueda', () {
      // La coincidencia de MEDICION.md: rueda 3× encima del motor 1×.
      expect(
        Linea.m1.frecuencia(80, 5)! / Linea.r3.frecuencia(80, null)!,
        closeTo(1.0, 0.002),
      );
    });

    test('ruido solo: ninguna línea sobresale de verdad', () {
      final v = ventana({})!;
      for (final m in v.lineas.values) {
        expect(m.veces, lessThan(5));
      }
    });

    test('despacio o sin velocidad no se mide nada', () {
      expect(medirLineas(List.filled(512, 1), 200, kmh: 10), isEmpty);
      expect(medirLineas(List.filled(512, 1), 200, kmh: null), isEmpty);
    });

    test('a 50 Hz no se miden (el motor se pliega)', () {
      final x = senal({20: 0.05}).sublist(0, 250);
      final v = armarVentana(
        magnitud: x,
        tInicio: 0,
        tFin: 4980,
        cubeta: 6,
        kmh: 80,
      )!;
      expect(v.lineas, isEmpty);
    });

    test('ida y vuelta por la base y el reporte', () {
      final m = {
        Linea.r2: const MedidaDeLinea(5.1, -0.4),
        Linea.m2: const MedidaDeLinea(3.0, 1.2),
      };
      final vuelta = lineasDeTexto(lineasATexto(m));
      expect(vuelta[Linea.r2]!.veces, 5.1);
      expect(vuelta[Linea.m2]!.corrimiento, 1.2);
      expect(lineasAMapa(m), {
        'r2': [5.1, -0.4],
        'm2': [3.0, 1.2],
      });
      expect(lineasDeTexto('basura;r9:1:2;r1:x:1'), isEmpty);
    });
  });

  group('comparar las líneas contra su historia (sitd-55)', () {
    // Diez viajes normales: rueda 2× entre 4,5 y 5,5 veces, corrida ±0,3 %.
    Map<int, List<VentanaVibracion>> historia() => {
      for (var viaje = 1; viaje <= 10; viaje++)
        viaje: [
          for (var i = 0; i < 10; i++)
            conLinea(
              5 + 0.5 * math.sin(viaje * 7.0 + i),
              0.3 * math.cos(viaje * 3.0 + i),
              t: viaje * 1000 + i,
            ),
        ],
    };

    test('un viaje normal no se marca', () {
      final h = historia();
      final base = baseDeLineas(h, excepto: {10});
      expect(base['r2:6']!.suficiente, isTrue);
      expect(compararLineas(h[10]!, base), isEmpty);
    });

    test('una línea que crece al doble se marca', () {
      final h = historia();
      h[11] = [for (var i = 0; i < 10; i++) conLinea(10, 0, t: 11000 + i)];
      final d = compararLineas(h[11]!, baseDeLineas(h, excepto: {11}));
      expect(d.single.que, QueCambio.crece);
      expect(d.single.linea, Linea.r2);
      expect(d.single.texto, contains('Rueda, 2 veces por vuelta'));
    });

    test('una que se corre un 2 % se marca; un 0,5 % no', () {
      final h = historia();
      h[11] = [for (var i = 0; i < 10; i++) conLinea(5, -2, t: 11000 + i)];
      h[12] = [for (var i = 0; i < 10; i++) conLinea(5, 0.5, t: 12000 + i)];
      final base = baseDeLineas(h, excepto: {11, 12});
      expect(compararLineas(h[11]!, base).single.que, QueCambio.seCorre);
      expect(compararLineas(h[12]!, base), isEmpty);
    });

    test('se avisa sólo si se repite tres viajes seguidos', () {
      final h = historia();
      h[11] = [for (var i = 0; i < 10; i++) conLinea(10, 0, t: 11000 + i)];
      h[12] = [for (var i = 0; i < 10; i++) conLinea(10, 0, t: 12000 + i)];
      expect(anomaliasDeLineas(h, [12, 11, 10]), isEmpty);
      h[13] = [for (var i = 0; i < 10; i++) conLinea(10, 0, t: 13000 + i)];
      final a = anomaliasDeLineas(h, [13, 12, 11]);
      expect(a.single.viajes, 3);
      expect(a.single.aMapa()['linea'], 'r2');
    });

    test('una ventana con el teléfono movido no cuenta', () {
      final h = historia();
      h[11] = [
        for (var i = 0; i < 10; i++)
          VentanaVibracion(
            t: 11000 + i,
            cubeta: 6,
            hz: 201,
            muestras: 1000,
            rms: 0.5,
            pico: 1,
            bandas: List.filled(8, 0.1),
            movido: true,
            lineas: {Linea.r2: const MedidaDeLinea(10, 0)},
          ),
      ];
      expect(compararLineas(h[11]!, baseDeLineas(h, excepto: {11})), isEmpty);
    });
  });
}
