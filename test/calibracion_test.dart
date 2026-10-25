import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/audio/regimen.dart';
import 'package:sitd_hilux/features/calibracion/calibracion.dart';
import 'package:sitd_hilux/features/calibracion/prueba_motor.dart';
import 'package:sitd_hilux/features/vibracion/cobertura.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';
import 'package:sitd_hilux/features/vibracion/rueda.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';
import 'package:sitd_hilux/ui/pantalla_calibracion.dart';

// sitd-45: la pantalla de Calibración (Mauro, 25-oct-2026).
void main() {
  late Base base;
  late RegistroDeCalibraciones registro;

  setUp(() {
    base = Base.abrir(':memory:');
    registro = RegistroDeCalibraciones(base);
  });

  tearDown(() {
    // La vuelta medida es global: que una prueba no se la deje a otra.
    usarCircunferenciaMedida(null);
    base.cerrar();
  });

  group('la vuelta de la rueda', () {
    test('10 vueltas en 23,9 m dan 2,39 m por vuelta', () {
      final r = medidaDeRueda(vueltas: 10, metros: 23.9, presionPsi: 32);
      expect(r.problema, isNull);
      expect(r.datos!['circunferenciaM'], 2.39);
      expect(r.datos!['diametroM'], closeTo(2.39 / math.pi, 1e-4));
      expect(r.datos!['presionPsi'], 32);
    });

    test('lo que no es de esta rueda no pasa (un cero de más, una vuelta '
        'contada de menos)', () {
      expect(medidaDeRueda(vueltas: 10, metros: 239).datos, isNull);
      expect(medidaDeRueda(vueltas: 9, metros: 23.9).datos, isNull);
      expect(medidaDeRueda(vueltas: 0, metros: 23.9).datos, isNull);
      expect(medidaDeRueda(vueltas: 10, metros: null).problema, isNotNull);
    });

    test('guardada, pasa a ser la que usa la frecuencia de la rueda', () {
      final antes = frecuenciaDeRueda(60);
      expect(circunferenciaEsMedida, isFalse);
      registro.guardar(
        Calibracion(
          tipo: 'rueda',
          inicio: 1000,
          fin: 1000,
          datos: medidaDeRueda(vueltas: 10, metros: 23.5).datos!,
        ),
      );
      registro.aplicarRueda();
      expect(circunferenciaEsMedida, isTrue);
      expect(circunferencia, 2.35);
      expect(frecuenciaDeRueda(60), closeTo((60 / 3.6) / 2.35, 1e-9));
      expect(frecuenciaDeRueda(60), isNot(closeTo(antes, 1e-6)));
      // La banda de la rueda del reporte sale de la misma cuenta.
      expect(vueltasPorSegundo(60), frecuenciaDeRueda(60));
    });

    test('sin medida, la de siempre: π × 76 cm', () {
      registro.aplicarRueda();
      expect(circunferencia, closeTo(math.pi * 0.76, 1e-12));
    });

    test('una guardada que no es creíble no se usa', () {
      registro.guardar(
        const Calibracion(
          tipo: 'rueda',
          inicio: 1,
          datos: {'circunferenciaM': 9.9},
        ),
      );
      registro.aplicarRueda();
      expect(circunferenciaEsMedida, isFalse);
    });
  });

  group('la prueba con un peso', () {
    test('queda en curso hasta que se termina', () {
      final id = registro.guardar(
        const Calibracion(
          tipo: 'peso',
          inicio: 5000,
          datos: {'rueda': 'delantera izquierda', 'gramos': 40},
        ),
      );
      expect(registro.pesoEnCurso()?.id, id);
      registro.cerrar(id, 9000);
      expect(registro.pesoEnCurso(), isNull);
      final c = registro.ultimas(tipo: 'peso').single;
      expect(c.fin, 9000);
      expect(c.datos['gramos'], 40);
    });

    test('cerrar dos veces no corre el fin', () {
      final id = registro.guardar(
        const Calibracion(tipo: 'peso', inicio: 1, datos: {}),
      );
      registro.cerrar(id, 10);
      registro.cerrar(id, 99);
      expect(registro.ultimas().single.fin, 10);
    });
  });

  group('la prueba del motor', () {
    test('ralentí un minuto y 45 s en cada régimen, en ese orden', () {
      expect([for (final p in pasosDelMotor) p.rpm], [null, 1000, 1500, 2000]);
      expect(pasosDelMotor.first.segundos, 60);
      expect(pasosDelMotor.skip(1).every((p) => p.segundos == 45), isTrue);
      final total = pasosDelMotor.fold<int>(
        0,
        (s, p) => s + p.segundos + p.acomodo,
      );
      expect(total, 230); // casi cuatro minutos
    });

    VentanaVibracion ventana(double rms, List<double> picos) =>
        VentanaVibracion(
          t: 1,
          cubeta: cubetaParado,
          hz: 200,
          muestras: 1000,
          rms: rms,
          pico: rms * 3,
          bandas: List.filled(cantidadDeBandas, rms),
          picos: picos,
        );

    LecturaMotor oido(double? rpm) => LecturaMotor(
      rpm: rpm,
      prominenciaDb: 12,
      nivelDb: -30,
      saturadas: 0,
      bandas: const [1, 2, 3],
    );

    test(
      'el resumen son medianas, y dice si el motor se ve en la vibración',
      () {
        final r = resumirPaso(
          pasosDelMotor[2], // 1500 RPM: el encendido en 50 Hz
          [
            ventana(0.1, [50.1, 9, 33, 3]),
            ventana(0.3, [49.9, 8, 70, 2]),
            ventana(0.2, [50.0, 7]),
          ],
          [oido(1490), oido(null), oido(1510), oido(1500)],
        );
        expect(r['rpmTacometro'], 1500);
        expect(r['ventanas'], 3);
        expect(r['rms'], 0.2);
        expect(r['escuchas'], 4);
        expect(r['escuchasConRpm'], 3);
        expect(r['rpmOida'], 1500);
        expect(r['encendidoHz'], 50);
        expect(r['encendidoEnVibracion'], isTrue);
        expect((r['picosVibracion'] as List).take(2), [50.0, 3.0]);
      },
    );

    test('sin el encendido entre los picos, lo dice', () {
      final r = resumirPaso(pasosDelMotor[3], [
        ventana(0.1, [20, 5]),
      ], const []);
      expect(r['encendidoHz'], closeTo(66.67, 0.01));
      expect(r['encendidoEnVibracion'], isFalse);
      expect(r.containsKey('rpmOida'), isFalse);
    });

    test('un pico que aparece en una sola ventana pesa menos que uno fijo', () {
      final p = picosFrecuentes([
        [12.1, 5, 30.0, 2],
        [12.0, 4],
        [11.9, 6, 44, 9],
      ]);
      expect(p.take(2), [12.0, 3.0]);
    });
  });

  testWidgets('la pantalla abre, y guarda la vuelta de la rueda', (t) async {
    await t.pumpWidget(MaterialApp(home: PantallaCalibracion(base: base)));
    expect(find.text('Calibración'), findsOneWidget);
    expect(
      find.textContaining('Hoy usa el diámetro de siempre'),
      findsOneWidget,
    );
    await t.enterText(find.widgetWithText(TextField, 'Metros medidos'), '23,9');
    await t.ensureVisible(find.text('Guardar la medida'));
    await t.pumpAndSettle();
    await t.tap(find.text('Guardar la medida'));
    await t.pump();
    expect(registro.ultimas(tipo: 'rueda'), hasLength(1));
    expect(circunferenciaEsMedida, isTrue);
  });

  testWidgets('con un viaje midiendo, la prueba del motor no arranca', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: PantallaCalibracion(base: base, hayViajeMidiendo: true),
      ),
    );
    await t.scrollUntilVisible(
      find.textContaining('Hay un viaje midiendo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final boton = t.widget<FilledButton>(
      find.ancestor(
        of: find.text('Empezar la prueba del motor'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(boton.onPressed, isNull);
  });
}
