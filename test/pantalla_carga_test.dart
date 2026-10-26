import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/combustible/carga.dart';
import 'package:sitd_hilux/ui/pantalla_carga.dart';

/// El formulario de la carga (`sitd-51` y `sitd-53`): hay que elegir hasta
/// el corte o parcial, y la carga se guarda con dónde se hizo.
void main() {
  Future<Carga?> llenar(
    WidgetTester tester, {
    required Future<LugarDeCarga?> Function() ubicar,
    bool elegir = true,
  }) async {
    Carga? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              resultado = await Navigator.of(c).push<Carga>(
                MaterialPageRoute(
                  builder: (_) => PantallaCarga(ubicar: ubicar),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), '40');
    await tester.enterText(campos.at(1), '254300');
    if (elegir) {
      await tester.ensureVisible(find.text('Parcial'));
      await tester.tap(find.text('Parcial'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Guardar la carga'));
    await tester.pumpAndSettle();
    return resultado;
  }

  testWidgets('se guarda con la ubicación de la estación', (tester) async {
    final c = await llenar(
      tester,
      ubicar: () async => (lat: -34.9, lon: -56.2, precision: 9.0),
    );
    expect(c, isNotNull);
    expect(c!.tanqueLleno, isFalse);
    expect(c.lat, -34.9);
    expect(c.lon, -56.2);
    expect(c.precisionM, 9.0);
  });

  testWidgets('sin ubicación, se guarda igual', (tester) async {
    final c = await llenar(tester, ubicar: () async => null);
    expect(c, isNotNull);
    expect(c!.tieneLugar, isFalse);
    expect(find.text('Sin ubicación: la carga se guarda igual'), findsNothing);
  });

  testWidgets('sin elegir hasta el corte o parcial, no se guarda', (
    tester,
  ) async {
    final c = await llenar(tester, ubicar: () async => null, elegir: false);
    expect(c, isNull);
    expect(
      find.textContaining('hasta el corte o fue una carga parcial'),
      findsOneWidget,
    );
  });
}
