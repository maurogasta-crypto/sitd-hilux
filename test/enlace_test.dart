import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/enlace/enlace.dart';

// sitd-57, general:C4: el viaje a la Pizarra de este teléfono, sin datos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('prueba/enlace');
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => mensajero.setMockMethodCallHandler(canal, null));

  group('los mensajes', () {
    test('ninguno lleva una coordenada, ni con todos los campos', () {
      final todos = [
        mensajeVivo(kmh: 82.44, km: 34.256, rpm: 2104.4, marcha: 5),
        mensajeVivo(km: 0),
        eventoEmpezo(),
        eventoTermino(km: 12.3, ms: 3725000),
        eventoLinea('rueda 1× crece en 60-70 km/h'),
      ];
      for (final m in todos) {
        for (final k in m.keys) {
          expect([
            'lat',
            'lon',
            'latitud',
            'longitud',
            'posicion',
          ], isNot(contains(k.toLowerCase())));
        }
        // Y el texto entero, por si un número suelto parece una posición.
        expect(jsonEncode(m), isNot(matches(RegExp(r'-\d{2}\.\d{4,}'))));
        expect(['vivo', 'evento'], contains(m['tipo']));
      }
    });

    test('el vivo redondea y deja afuera lo que no se sabe', () {
      expect(mensajeVivo(kmh: 82.44, km: 34.256, rpm: 2104.4, marcha: 5), {
        'tipo': 'vivo',
        'kmh': 82.4,
        'km': 34.26,
        'rpm': 2104,
        'marcha': 5,
      });
      expect(mensajeVivo(km: 1), {'tipo': 'vivo', 'km': 1.0});
    });

    test('el viaje terminado dice km y duración', () {
      expect(
        eventoTermino(km: 12.34, ms: 25 * 60000)['texto'],
        '12,3 km en 25 min.',
      );
      expect(
        eventoTermino(km: 140, ms: 125 * 60000)['texto'],
        '140,0 km en 2 h 05 min.',
      );
    });
  });

  group('EnlaceConPizarra', () {
    test('manda el JSON por el canal y dice si lo tomó', () async {
      Object? recibido;
      mensajero.setMockMethodCallHandler(canal, (c) async {
        recibido = (c.arguments as Map)['mensaje'];
        return true;
      });
      final e = EnlaceConPizarra(canal: canal);
      expect(await e.enviar(eventoEmpezo()), isTrue);
      expect(jsonDecode(recibido! as String)['tipo'], 'evento');
    });

    test('sin Pizarra no tira, y a los tres «no» descansa un minuto', () async {
      var llamadas = 0;
      mensajero.setMockMethodCallHandler(canal, (c) async {
        llamadas++;
        throw PlatformException(code: 'no');
      });
      var ahora = 1000;
      final e = EnlaceConPizarra(canal: canal, reloj: () => ahora);
      for (var i = 0; i < 5; i++) {
        expect(await e.enviar(mensajeVivo(km: 1)), isFalse);
      }
      expect(llamadas, 3);
      ahora += EnlaceConPizarra.descansoMs;
      await e.enviar(mensajeVivo(km: 1));
      expect(llamadas, 4);
    });

    test('un canal sin registrar es un «no», no una falla', () async {
      final e = EnlaceConPizarra(canal: const MethodChannel('nadie/escucha'));
      expect(await e.enviar(eventoEmpezo()), isFalse);
    });
  });
}
