import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/nube/cola.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/reintento.dart';
import 'package:sitd_hilux/features/nube/servicio_nube.dart';
import 'package:sitd_hilux/features/nube/subida.dart';

import 'recorrido_nube_test.dart' show credencialPegada;

/// Una red que nunca contesta: ni error ni respuesta.
class Colgada extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest pedido) =>
      Completer<http.StreamedResponse>().future;
}

void main() {
  group('reintentar cuando vuelve la señal (sitd-55)', () {
    var ahora = 0;
    Reintento nuevo() => Reintento(reloj: () => ahora);

    test('sin fallas y sin cola, no toca', () {
      expect(nuevo().toca(enCola: 0, corriendo: false), isFalse);
    });

    test('con viajes en la cola toca enseguida, salvo que ya corra otra', () {
      final r = nuevo();
      expect(r.toca(enCola: 2, corriendo: false), isTrue);
      expect(r.toca(enCola: 2, corriendo: true), isFalse);
    });

    test('después de una falla espera, y cada falla dobla la espera', () {
      ahora = 0;
      final r = nuevo()..resultado(salioBien: false);
      expect(r.toca(enCola: 0, corriendo: false), isFalse);
      ahora = Reintento.primera.inMilliseconds;
      expect(r.toca(enCola: 0, corriendo: false), isTrue);
      r.resultado(salioBien: false);
      expect(r.espera, Reintento.primera * 2);
      for (var i = 0; i < 10; i++) {
        r.resultado(salioBien: false);
      }
      expect(r.espera, Reintento.tope);
    });

    test('una que sale bien vuelve a empezar de cero', () {
      final r = nuevo()
        ..resultado(salioBien: false)
        ..resultado(salioBien: false)
        ..resultado(salioBien: true);
      expect(r.pendiente, isFalse);
      expect(r.espera, Reintento.primera);
      expect(r.toca(enCola: 0, corriendo: false), isFalse);
    });

    test('hayRed nunca tira, aunque el nombre no exista', () async {
      expect(await hayRed(servidor: 'no-existe.invalid'), isFalse);
    });
  });

  group('una sincronización colgada no traba a las que vienen (sitd-55)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('colgada'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('se corta al límite, dice en qué paso quedó, y suelta', () async {
      final base = Base.abrir('${dir.path}/a.db');
      final nube = ServicioNube(
        cola: ColaDeSubida(base),
        guarda: GuardaDeCredencial(base)..guardar(credencialPegada),
        // La espera de cada pedido, larguísima: lo que corta es el límite
        // de la sincronización entera.
        subida: Subida(cliente: Colgada(), espera: const Duration(hours: 1)),
        armar: (v) => {'viajes': []},
      );
      final primera = nube.sincronizar(
        base: base,
        ruta: '${dir.path}/a.db',
        carpeta: dir.path,
        limite: const Duration(milliseconds: 50),
      );
      expect(nube.sincronizando, isTrue);
      final r = await primera;
      expect(r.falla, contains('no terminó'));
      expect(r.falla, contains('Mirando qué hay en la nube'));
      expect(nube.sincronizando, isFalse);

      // La siguiente es una nueva, no la colgada.
      final segunda = nube.sincronizar(
        base: base,
        ruta: '${dir.path}/a.db',
        carpeta: dir.path,
        limite: const Duration(milliseconds: 50),
      );
      expect(identical(segunda, primera), isFalse);
      await segunda;
      base.cerrar();
    });
  });
}
