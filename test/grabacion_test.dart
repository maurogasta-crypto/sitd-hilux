import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/grabacion/grabacion.dart';
import 'package:sitd_hilux/features/nube/cola.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/servicio_nube.dart';
import 'package:sitd_hilux/features/nube/subida.dart';
import 'package:sitd_hilux/features/respaldo/saneado.dart';
import 'package:sitd_hilux/features/vibracion/sacudon.dart';

import 'recorrido_nube_test.dart' show NubeFalsa, credencialPegada;

void main() {
  late Directory dir;
  late Base base;
  late RegistroDeGrabaciones registro;
  var ahora = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('grabacion');
    base = Base.abrir('${dir.path}/a.db');
    registro = RegistroDeGrabaciones(base);
    ahora = DateTime(2026, 10, 26, 10).millisecondsSinceEpoch;
  });
  tearDown(() {
    base.cerrar();
    dir.deleteSync(recursive: true);
  });

  Grabador grabador() => Grabador(
    registro: registro,
    // 200 Hz de acelerómetro, con sus tres ejes.
    acelerometro: (desde, hasta) => [
      for (var t = desde; t <= hasta; t += 5)
        Sacudon(t, 9.81, x: 0.1, y: 0.2, z: 9.8),
    ],
    reloj: () => ahora,
  );

  final segundo = List<int>.filled(8000, 1000);

  /// Pasa [n] segundos de micrófono; devuelve la última respuesta.
  Grabacion? pasar(
    Grabador g,
    int n, {
    double? kmh = 80,
    bool musica = false,
    bool llamada = false,
  }) {
    Grabacion? ultima;
    for (var i = 0; i < n; i++) {
      ahora += 1000;
      ultima = g.trozo(
        segundo,
        t: ahora,
        kmh: kmh,
        marcha: 5,
        musica: musica,
        llamada: llamada,
      );
    }
    return ultima;
  }

  group('grabar 10 s (sitd-55)', () {
    test('sin pedido no junta nada: el micrófono sigue sin guardar sonido', () {
      final g = grabador()..empezarViaje(1);
      expect(pasar(g, 20), isNull);
      expect(registro.ultimas(), isEmpty);
    });

    test('a mano: diez segundos de sonido y la señal del acelerómetro', () {
      final g = grabador()..empezarViaje(1);
      expect(g.pedirAMano(), isNull);
      expect(pasar(g, 9), isNull);
      final r = pasar(g, 1)!;
      expect(r.segundosDeAudio, 10);
      expect(r.muestrasDeVibracion, greaterThan(1900));
      expect(r.hzVib, closeTo(200, 1));
      expect(r.marcha, 5);
      expect(registro.sinSubir(), hasLength(1));
      // Y después no sigue grabando.
      expect(pasar(g, 20), isNull);
      expect(registro.sinSubir(), hasLength(1));
    });

    test('con una llamada o con música se tira lo juntado y se espera', () {
      final g = grabador()..empezarViaje(1);
      g.pedirAMano();
      pasar(g, 6);
      pasar(g, 1, llamada: true);
      expect(g.juntados, 0);
      pasar(g, 6);
      pasar(g, 1, musica: true);
      expect(registro.sinSubir(), isEmpty);
      expect(pasar(g, 10), isNotNull);
    });

    test('la automática espera su velocidad, y se hace una sola vez', () {
      registro.pedir(const PedidoDeGrabar('línea r2 creció', cubeta: 6));
      final g = grabador()..empezarViaje(1);
      // 50 km/h es la cubeta 3: no es la de la línea.
      expect(pasar(g, 12, kmh: 50), isNull);
      // Abajo de 30 km/h tampoco.
      expect(pasar(g, 12, kmh: 25), isNull);
      final r = pasar(g, 10, kmh: 82)!;
      expect(r.motivo, 'línea r2 creció');
      expect(registro.pendiente, isNull);
      // El viaje siguiente ya no la vuelve a grabar.
      g
        ..terminarViaje()
        ..empezarViaje(2);
      expect(pasar(g, 12, kmh: 82), isNull);
    });

    test('hasta diez a mano por día', () {
      final g = grabador()..empezarViaje(1);
      for (var i = 0; i < maximoAManoPorDia; i++) {
        expect(g.pedirAMano(), isNull);
        expect(pasar(g, 10), isNotNull);
      }
      expect(g.pedirAMano(), contains('$maximoAManoPorDia'));
    });

    test('una a mano que no llegó no pasa al viaje siguiente', () {
      final g = grabador()..empezarViaje(1);
      g.pedirAMano();
      pasar(g, 3);
      g
        ..terminarViaje()
        ..empezarViaje(2);
      expect(g.pedido, isNull);
    });

    test('el PCM va en 16 bits little-endian, y la vibración en float32', () {
      final b = pcmABytes([
        [1, -2],
        [40000],
      ]);
      final d = ByteData.sublistView(b);
      expect(d.getInt16(0, Endian.little), 1);
      expect(d.getInt16(2, Endian.little), -2);
      expect(d.getInt16(4, Endian.little), 32767);
      final v = ByteData.sublistView(
        sacudonesABytes([const Sacudon(0, 9.8, x: 1, y: 2, z: 3)]),
      );
      expect(v.getFloat32(12, Endian.little), 3);
      expect(
        ByteData.sublistView(sacudonesABytes([const Sacudon(0, 9.8)]))
            .getFloat32(4, Endian.little)
            .isNaN,
        isTrue,
      );
    });
  });

  test('una copia completa no lleva el sonido de una que no subió', () {
    final g = grabador()..empezarViaje(1);
    g.pedirAMano();
    pasar(g, 10);
    final destino = '${dir.path}/copia.db';
    hacerCopiaSaneada(base: base, ruta: '${dir.path}/a.db', destino: destino);
    final copia = Base.abrir(destino);
    final f = copia.db.select('SELECT audio, vibracion FROM grabaciones');
    expect(f.single['audio'], isNull);
    expect(f.single['vibracion'], isNull);
    copia.cerrar();
    // En el teléfono sigue, hasta que suba.
    expect(registro.sinSubir().single.audio, isNotNull);
  });

  group('suben a grabaciones/ y se borran del teléfono (sitd-55)', () {
    test('sube con sus campos y le quedan la ficha sin el sonido', () async {
      final g = grabador()..empezarViaje(1);
      g.pedirAMano();
      pasar(g, 10);
      final nube = NubeFalsa();
      final s = ServicioNube(
        cola: ColaDeSubida(base),
        guarda: GuardaDeCredencial(base)..guardar(credencialPegada),
        subida: Subida(cliente: nube),
        armar: (v) => {'viajes': []},
        grabaciones: registro,
      );
      final t = await s.subirPendientes();
      expect(t.subidos, 1);
      final doc = nube.documentos.entries.singleWhere(
        (e) => e.key.startsWith('grabaciones/'),
      );
      expect(doc.value.containsKey('audio'), isTrue);
      expect(doc.value.containsKey('vibracion'), isTrue);
      // Ni una coordenada.
      expect(doc.value.keys, isNot(contains('lat')));
      expect(registro.sinSubir(), isEmpty);
      final queda = registro.ultimas().single;
      expect(queda.subida, isTrue);
      expect(queda.audio, isNull);
      // Volver a subir no la duplica.
      expect((await s.subirPendientes()).subidos, 0);
    });
  });
}
