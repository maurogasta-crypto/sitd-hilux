import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/nube/cola.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/servicio_nube.dart';
import 'package:sitd_hilux/features/nube/subida.dart';
import 'package:sitd_hilux/features/respaldo/reporte.dart';

/// Un servidor de mentira. Guarda lo que se le mandó para poder revisarlo:
/// la prueba que importa es sobre el texto que SALE del teléfono.
class ServidorFalso extends http.BaseClient {
  final List<String> cuerposEnviados = [];
  final List<Uri> urls = [];
  int codigoDeEscritura;
  bool loginOk;
  Object? explota;

  ServidorFalso({this.codigoDeEscritura = 200, this.loginOk = true});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest pedido) async {
    if (explota != null) throw explota!;
    urls.add(pedido.url);
    final cuerpo = pedido is http.Request ? pedido.body : '';

    if (pedido.url.host.contains('identitytoolkit')) {
      return _responder(
        loginOk ? 200 : 400,
        loginOk ? '{"idToken":"token-de-mentira"}' : '{"error":"malo"}',
      );
    }
    cuerposEnviados.add(cuerpo);
    return _responder(codigoDeEscritura, '{}');
  }

  http.StreamedResponse _responder(int codigo, String cuerpo) =>
      http.StreamedResponse(Stream.value(utf8.encode(cuerpo)), codigo);
}

const credencialDePrueba = Credencial(
  proyecto: 'proyecto-de-prueba',
  apiKey: 'clave-de-prueba',
  mail: 'telefono@ejemplo',
  clave: 'inventada-para-el-banco',
);

void main() {
  group('el servicio de nube', pruebasDelServicio);

  late Base base;
  late ColaDeSubida cola;

  setUp(() {
    base = Base.abrir(':memory:');
    base.db.execute(
      'INSERT INTO viajes (id, inicio, fin) VALUES (1, 1000, 2000)',
    );
    base.db.execute(
      'INSERT INTO viajes (id, inicio, fin) VALUES (2, 3000, 4000)',
    );
    cola = ColaDeSubida(base, reloj: () => 5000);
  });

  tearDown(() => base.cerrar());

  group('la cola', () {
    test('encolar dos veces el mismo viaje no lo duplica', () {
      cola.encolar(1);
      cola.encolar(1);
      expect(cola.cuantosFaltan, 1);
    });

    test('los pendientes salen del más viejo al más nuevo', () {
      ColaDeSubida(base, reloj: () => 200).encolar(2);
      ColaDeSubida(base, reloj: () => 100).encolar(1);
      expect(cola.pendientes().map((p) => p.viaje).toList(), [1, 2]);
    });

    // Un viaje sólo sale de la cola cuando subió. Que la red falle veinte
    // veces no es motivo para perderlo — la camioneta anda sin señal.
    test('una falla NO lo saca de la cola, sólo lo anota', () {
      cola.encolar(1);
      cola.marcarFalla(1, 'sin señal');
      cola.marcarFalla(1, 'sin señal');

      expect(cola.cuantosFaltan, 1);
      final p = cola.pendientes().single;
      expect(p.intentos, 2);
      expect(p.ultimoError, 'sin señal');
      expect(cola.estaSubido(1), isFalse);
    });

    test('marcarSubido lo saca de pendientes y limpia el error', () {
      cola.encolar(1);
      cola.marcarFalla(1, 'sin señal');
      cola.marcarSubido(1);

      expect(cola.cuantosFaltan, 0);
      expect(cola.cuantosSubidos, 1);
      expect(cola.estaSubido(1), isTrue);
    });

    test('borrar el viaje se lleva su fila: no quedan huérfanas', () {
      cola.encolar(1);
      base.db.execute('PRAGMA foreign_keys = ON');
      base.db.execute('DELETE FROM viajes WHERE id = 1');
      expect(cola.cuantosFaltan, 0);
    });
  });

  group('la credencial', () {
    test('sin configurar, no está configurada y no rompe nada', () {
      final g = GuardaDeCredencial(base);
      expect(g.credencial, isNull);
      expect(g.configurada, isFalse);
    });

    test('un pegado completo se guarda y sobrevive a reabrir', () {
      final g = GuardaDeCredencial(base);
      final error = g.guardar(
        '{"proyecto":"p","apiKey":"k","mail":"m@e","clave":"c"}',
      );
      expect(error, isNull);
      expect(GuardaDeCredencial(base).credencial!.proyecto, 'p');
      expect(GuardaDeCredencial(base).configurada, isTrue);
    });

    test('un pegado roto da un MENSAJE, no una excepción', () {
      final g = GuardaDeCredencial(base);
      expect(g.guardar('esto no es json'), contains('configuración'));
      expect(g.configurada, isFalse);
    });

    test('si falta un campo lo dice, y no guarda a medias', () {
      final g = GuardaDeCredencial(base);
      expect(g.guardar('{"proyecto":"p","apiKey":"k"}'), contains('Falta'));
      expect(g.configurada, isFalse);
    });

    // La pantalla de ajustes es la que uno fotografía para pedir ayuda.
    test('el resumen NUNCA muestra la contraseña', () {
      expect(credencialDePrueba.resumen, isNot(contains('inventada')));
      expect(credencialDePrueba.resumen, contains('telefono@ejemplo'));
    });

    test('el molde que se muestra no trae ningún valor', () {
      final m = leerPegado(moldeDeCredencial)!;
      expect(m.completa, isFalse);
      expect(m.proyecto, isEmpty);
      expect(m.clave, isEmpty);
    });
  });

  group('subir', () {
    test('sin configurar ni lo intenta', () async {
      final s = ServidorFalso();
      final r = await Subida(cliente: s).subir(
        credencial: const Credencial(
          proyecto: '',
          apiKey: '',
          mail: '',
          clave: '',
        ),
        id: 'x',
        reporte: const {},
      );
      expect(r.ok, isFalse);
      expect(r.esCulpaNuestra, isTrue);
      expect(s.urls, isEmpty);
    });

    test(
      'con la contraseña mal, dice que es culpa nuestra y no reintenta',
      () async {
        final s = ServidorFalso(loginOk: false);
        final r = await Subida(cliente: s).subir(
          credencial: credencialDePrueba,
          id: 'x',
          reporte: const {'a': 1},
        );
        expect(r.ok, isFalse);
        expect(r.esCulpaNuestra, isTrue);
        expect(r.falla, contains('contraseña'));
        // No llegó a escribir.
        expect(s.cuerposEnviados, isEmpty);
      },
    );

    // Sin señal es el caso NORMAL en una camioneta, no un error.
    test('sin señal no lanza: devuelve el motivo y se reintenta', () async {
      final s = ServidorFalso()..explota = Exception('host no resuelve');
      final r = await Subida(
        cliente: s,
      ).subir(credencial: credencialDePrueba, id: 'x', reporte: const {'a': 1});
      expect(r.ok, isFalse);
      expect(r.esCulpaNuestra, isFalse);
      expect(r.falla, contains('No se pudo llegar'));
    });

    test('que YA estuviera subido no es una falla', () async {
      final s = ServidorFalso(codigoDeEscritura: 409);
      final r = await Subida(
        cliente: s,
      ).subir(credencial: credencialDePrueba, id: 'x', reporte: const {'a': 1});
      expect(r.ok, isTrue);
    });

    test('un 403 manda a revisar las reglas, y no se reintenta solo', () async {
      final s = ServidorFalso(codigoDeEscritura: 403);
      final r = await Subida(
        cliente: s,
      ).subir(credencial: credencialDePrueba, id: 'x', reporte: const {'a': 1});
      expect(r.ok, isFalse);
      expect(r.esCulpaNuestra, isTrue);
      expect(r.falla, contains('reglas'));
    });

    test(
      'escribe en la colección reportes del proyecto que se configuró',
      () async {
        final s = ServidorFalso();
        await Subida(cliente: s).subir(
          credencial: credencialDePrueba,
          id: 'telefono-viaje-7',
          reporte: const {
            'app': {'sello': 'sitd-17'},
            'generado': 99,
          },
        );
        final url = s.urls.last.toString();
        expect(url, contains('projects/proyecto-de-prueba'));
        expect(url, contains('/documents/reportes'));
        expect(url, contains('documentId=telefono-viaje-7'));
      },
    );

    test('la contraseña no viaja en la escritura, sólo en el login', () async {
      final s = ServidorFalso();
      await Subida(
        cliente: s,
      ).subir(credencial: credencialDePrueba, id: 'x', reporte: const {'a': 1});
      expect(s.cuerposEnviados.single, isNot(contains('inventada')));
    });
  });
}

/// Lo que se agrega al final del archivo: el servicio que junta todo, y la
/// prueba que sostiene la única regla que no se negocia.
void pruebasDelServicio() {
  late Base base;
  late ColaDeSubida cola;
  late GuardaDeCredencial guarda;

  setUp(() {
    base = Base.abrir(':memory:');
    for (var i = 1; i <= 3; i++) {
      base.db.execute('INSERT INTO viajes (id, inicio, fin) VALUES (?, ?, ?)', [
        i,
        i * 1000,
        i * 1000 + 500,
      ]);
    }
    cola = ColaDeSubida(base, reloj: () => 9000);
    guarda = GuardaDeCredencial(base)
      ..guardar('{"proyecto":"p","apiKey":"k","mail":"tel@e","clave":"c"}');
  });

  tearDown(() => base.cerrar());

  ServicioNube armarServicio(
    ServidorFalso s, {
    Map<String, dynamic> Function(int)? armar,
  }) => ServicioNube(
    cola: cola,
    guarda: guarda,
    subida: Subida(cliente: s),
    armar:
        armar ??
        (v) => {
          'viaje': v,
          'generado': 1,
          'app': {'sello': 's'},
        },
  );

  // LA prueba de esta etapa. El respaldo completo lleva dónde estuvo la
  // camioneta minuto a minuto y NO sale del teléfono por ningún canal — ni
  // por un chat ni por una nube. Si alguien cambiara el alcance, esto falla.
  test('lo que SALE del teléfono no lleva una sola coordenada', () async {
    expect(alcanceQueSeSube, Alcance.paraDesarrollo);

    final s = ServidorFalso();
    cola.encolar(1);
    await armarServicio(
      s,
      // Un reporte con pinta de completo, para que la prueba tenga qué revisar.
      armar: (v) => {
        'viaje': v,
        'generado': 1,
        'app': {'sello': 's'},
        'sinRecorrido': true,
        'analisis': {
          'parametros': {'umbralDeDesvio': 6},
        },
      },
    ).subirPendientes();

    final enviado = s.cuerposEnviados.single;
    expect(enviado, isNot(contains('"lat"')));
    expect(enviado, isNot(contains('"lon"')));
    expect(enviado, isNot(contains('-34.9')));
    expect(enviado, isNot(contains('-56.1')));
    // Y que la prueba esté mirando algo de verdad.
    expect(enviado, contains('sinRecorrido'));
  });

  test('sube los pendientes y los saca de la cola', () async {
    cola
      ..encolar(1)
      ..encolar(2);
    final t = await armarServicio(ServidorFalso()).subirPendientes();

    expect(t.subidos, 2);
    expect(t.fallaron, 0);
    expect(cola.cuantosFaltan, 0);
  });

  test('sin señal no pierde nada: quedan en la cola para después', () async {
    cola
      ..encolar(1)
      ..encolar(2);
    final s = ServidorFalso()..explota = Exception('sin red');
    final t = await armarServicio(s).subirPendientes();

    expect(t.subidos, 0);
    expect(t.fallaron, 2);
    expect(t.pararDeIntentar, isFalse);
    expect(cola.cuantosFaltan, 2, reason: 'no se puede perder un viaje');
  });

  // Insistir con los otros diecinueve sólo gasta batería y llena la cola con
  // la misma falla repetida.
  test('si la contraseña está mal, corta y no castiga a los demás', () async {
    cola
      ..encolar(1)
      ..encolar(2)
      ..encolar(3);
    final t = await armarServicio(ServidorFalso(loginOk: false))
        .subirPendientes();

    expect(t.pararDeIntentar, isTrue);
    expect(t.fallaron, 1, reason: 'cortó en el primero');
    expect(cola.cuantosFaltan, 3);
  });

  test('sin configurar avisa y no toca la red', () async {
    guarda.olvidar();
    cola.encolar(1);
    final s = ServidorFalso();
    final t = await armarServicio(s).subirPendientes();

    expect(t.pararDeIntentar, isTrue);
    expect(t.primeraFalla, contains('no está configurada'));
    expect(s.urls, isEmpty);
    expect(cola.cuantosFaltan, 1);
  });

  test('sin nada pendiente no habla con nadie', () async {
    final s = ServidorFalso();
    final t = await armarServicio(s).subirPendientes();
    expect(t.huboAlgo, isFalse);
    expect(s.urls, isEmpty);
  });

  test('dos teléfonos no se pisan el viaje 1', () async {
    final s = ServidorFalso();
    cola.encolar(1);
    await armarServicio(s).subirPendientes();
    expect(s.urls.last.toString(), contains('documentId=tel-viaje-1'));
  });
}
