import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/aparato.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/respaldo/importar.dart';

// sitd-44, hilux:D5: en qué teléfono se midió cada viaje.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('prueba/aparato');

  group('textoDelTelefono', () {
    test('saca la marca repetida y los espacios de más', () {
      expect(
        textoDelTelefono('Xiaomi  Xiaomi 23100RN82L '),
        'Xiaomi 23100RN82L',
      );
      expect(textoDelTelefono('Xiaomi Redmi Note 9'), 'Xiaomi Redmi Note 9');
      expect(textoDelTelefono('samsung SM-A156M'), 'samsung SM-A156M');
    });

    test('nada o vacío no es un teléfono', () {
      expect(textoDelTelefono(null), isNull);
      expect(textoDelTelefono('   '), isNull);
    });

    test('tiene techo', () {
      expect(textoDelTelefono('x' * 200)!.length, 60);
    });
  });

  group('anotarTelefono', () {
    late Base base;
    setUp(() => base = Base.abrir(':memory:'));
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
      base.cerrar();
    });

    test('lo que contesta el sistema queda en ajustes', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (c) async => 'Xiaomi Redmi Note 9');
      await anotarTelefono(base, canal: canal);
      expect(base.leerAjuste(claveDelTelefono), 'Xiaomi Redmi Note 9');
    });

    test('si el canal no contesta, no tira y no anota nada', () async {
      await anotarTelefono(base, canal: canal);
      expect(base.leerAjuste(claveDelTelefono), isNull);
    });

    test('el teléfono no viaja en un respaldo: ajustes no se importa', () {
      expect(tablasQueNoSeImportan, contains('ajustes'));
    });
  });
}
