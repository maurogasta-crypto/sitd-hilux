import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/nube/cola.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/servicio_nube.dart';
import 'package:sitd_hilux/features/nube/subida.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/respaldo/importar.dart';

/// Una nube de mentira que se acuerda de lo que le escribieron, para que la
/// vuelta completa —subir y bajar— se pueda probar sin red.
class NubeFalsa extends http.BaseClient {
  final Map<String, Map<String, dynamic>> documentos = {};
  final List<Uri> urls = [];
  int codigoDeEscritura = 200;
  bool loginOk = true;
  bool dejaLeer = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest pedido) async {
    urls.add(pedido.url);
    final u = pedido.url;

    if (u.host.contains('identitytoolkit') || u.host.contains('securetoken')) {
      return _r(loginOk ? 200 : 400, '{"idToken":"token","refreshToken":"r"}');
    }

    final ruta = u.pathSegments;
    final coleccion = ruta.contains('recorridos') ? 'recorridos' : 'reportes';

    if (pedido.method == 'POST') {
      if (codigoDeEscritura != 200) return _r(codigoDeEscritura, '{}');
      final id = u.queryParameters['documentId']!;
      final clave = '$coleccion/$id';
      if (documentos.containsKey(clave)) return _r(409, '{}');
      final cuerpo = jsonDecode((pedido as http.Request).body) as Map;
      documentos[clave] = (cuerpo['fields'] as Map).cast<String, dynamic>();
      return _r(200, '{}');
    }

    if (!dejaLeer) return _r(403, '{}');

    // Traer uno.
    final ultimo = ruta.last;
    if (ultimo != 'recorridos') {
      final d = documentos['recorridos/$ultimo'];
      if (d == null) return _r(404, '{}');
      return _r(200, jsonEncode({'name': 'x/$ultimo', 'fields': d}));
    }

    // Listar.
    return _r(
      200,
      jsonEncode({
        'documents': [
          for (final e in documentos.entries)
            if (e.key.startsWith('recorridos/'))
              {'name': 'x/${e.key.split('/').last}', 'fields': e.value},
        ],
      }),
    );
  }

  http.StreamedResponse _r(int codigo, String cuerpo) =>
      http.StreamedResponse(Stream.value(utf8.encode(cuerpo)), codigo);
}

const credencial = Credencial(
  proyecto: 'proyecto-de-prueba',
  apiKey: 'clave-de-prueba',
  mail: 'telefono@ejemplo',
  clave: 'inventada-para-el-banco',
);

/// Siembra un viaje con puntos que se mueven de verdad.
int sembrarViaje(Base base, {required int inicio, int puntos = 40}) {
  final r = RegistroDeViajes(base);
  final id = r.abrir(inicio: inicio, odoTablero: 405100);
  var lat = -34.90;
  var lon = -56.16;
  var alt = 412.0;
  for (var i = 0; i < puntos; i++) {
    lat += 0.0002;
    lon += 0.0001;
    alt += 0.7;
    r.guardarPunto(
      id,
      Muestra(
        t: inicio + i * 1000,
        lat: lat,
        lon: lon,
        alt: alt,
        velocidad: 20,
        precision: 4.5,
        precisionVel: 0.3,
      ),
    );
  }
  r.recalcular(id);
  r.cerrar(id, fin: inicio + puntos * 1000, odoTablero: 405120);
  return id;
}

/// La configuración tal como la pega Mauro en el teléfono: un texto, no un
/// objeto. Es lo que espera `GuardaDeCredencial.guardar`.
final credencialPegada = jsonEncode({
  'proyecto': credencial.proyecto,
  'apiKey': credencial.apiKey,
  'mail': credencial.mail,
  'clave': credencial.clave,
});

ServicioNube armarServicio(Base base, NubeFalsa nube) => ServicioNube(
  cola: ColaDeSubida(base),
  guarda: GuardaDeCredencial(base)..guardar(credencialPegada),
  subida: Subida(cliente: nube),
  armar: (v) => {'viajes': []},
  viajes: RegistroDeViajes(base),
);

void main() {
  late Base base;
  late NubeFalsa nube;

  setUp(() {
    base = Base.abrir(':memory:');
    nube = NubeFalsa();
  });

  tearDown(() => base.cerrar());

  group('subir el recorrido', () {
    test('sube los viajes que hay, uno por documento', () {
      sembrarViaje(base, inicio: 1000000);
      sembrarViaje(base, inicio: 2000000);

      return armarServicio(base, nube).subirRecorridos().then((t) {
        expect(t.subidos, 2);
        expect(t.fallaron, 0);
        expect(
          nube.documentos.keys.where((k) => k.startsWith('recorridos/')),
          hasLength(2),
        );
      });
    });

    test('el documento se llama por el INSTANTE, no por el número local', () {
      /* Es el arreglo de `sitd-26`. El número que un viaje tiene en el
         teléfono cambia al sumar o reemplazar un respaldo; el instante en que
         arrancó, no. Con el número, un viaje nuevo podía caer sobre el
         documento de otro, rebotar con 409, y la aplicación lo leería como
         «ya estaba»: ese viaje nunca se subiría y nada lo diría. */
      sembrarViaje(base, inicio: 1758489000000);
      return armarServicio(base, nube).subirRecorridos().then((_) {
        expect(nube.documentos.keys, contains(contains('1758489000000')));
        expect(
          nube.documentos.keys.any((k) => k.contains('viaje-1')),
          isFalse,
          reason: 'volvió a usar el número local, que no es estable',
        );
      });
    });

    test('no vuelve a subir lo que ya está arriba', () async {
      sembrarViaje(base, inicio: 1000000);
      final s = armarServicio(base, nube);
      final primera = await s.subirRecorridos();
      final segunda = await s.subirRecorridos();

      expect(primera.subidos, 1);
      expect(segunda.subidos, 0);
      expect(segunda.yaEstaban, 1);
      expect(nube.documentos, hasLength(1));
    });

    test('«ya estaban» se cuenta aparte de «fallaron»', () async {
      /* Sin esa distinción, tocar el botón dos veces mostraría «0 subidos» y
         parecería roto cuando lo que pasó es que no había nada que subir. */
      sembrarViaje(base, inicio: 1000000);
      final s = armarServicio(base, nube);
      await s.subirRecorridos();
      final t = await s.subirRecorridos();
      expect(t.fallaron, 0);
      expect(t.resumen, contains('ya estaban'));
    });

    test('la ficha del viaje viaja al lado del recorrido', () async {
      sembrarViaje(base, inicio: 1000000);
      await armarServicio(base, nube).subirRecorridos();
      final doc = nube.documentos.values.first;
      final ficha = jsonDecode(
        doc['viaje']['stringValue'] as String,
      ) as Map<String, dynamic>;
      expect(ficha['inicio'], 1000000);
      expect(ficha['odoTableroIni'], 405100);
      expect(ficha['odoTableroFin'], 405120);
      expect(ficha['metros'], greaterThan(0));
    });

    test('sin credencial no se intenta nada', () async {
      sembrarViaje(base, inicio: 1000000);
      final s = ServicioNube(
        cola: ColaDeSubida(base),
        guarda: GuardaDeCredencial(base),
        subida: Subida(cliente: nube),
        armar: (v) => {},
        viajes: RegistroDeViajes(base),
      );
      final t = await s.subirRecorridos();
      expect(t.subidos, 0);
      expect(t.falla, contains('no está configurada'));
      expect(nube.urls, isEmpty);
    });

    test('un viaje sin puntos no ocupa un documento', () async {
      RegistroDeViajes(base).abrir(inicio: 5000);
      final t = await armarServicio(base, nube).subirRecorridos();
      expect(t.subidos, 0);
      expect(nube.documentos, isEmpty);
    });

    test('si las reglas rechazan, se dice y no se sigue intentando', () async {
      sembrarViaje(base, inicio: 1000000);
      sembrarViaje(base, inicio: 2000000);
      nube.codigoDeEscritura = 403;
      final t = await armarServicio(base, nube).subirRecorridos();
      expect(t.fallaron, 1, reason: 'tendría que haber cortado en la primera');
      expect(t.falla, contains('reglas'));
    });
  });

  group('la vuelta completa: teléfono -> nube -> teléfono', () {
    test('el viaje vuelve con sus puntos y sus kilómetros', () async {
      final id = sembrarViaje(base, inicio: 1758489000000, puntos: 60);
      final original = RegistroDeViajes(base).porId(id)!;
      await armarServicio(base, nube).subirRecorridos();

      // Un teléfono nuevo, vacío.
      final otro = Base.abrir(':memory:');
      final bajada = await Subida(cliente: nube).bajarRecorrido(
        credencial: credencial,
        id: nube.documentos.keys.first.split('/').last,
      );
      expect(bajada.hay, isTrue, reason: bajada.falla);

      final r = meterViajeDeLaNube(
        viva: otro,
        recorrido: bajada.texto!,
        ficha: bajada.ficha,
      );
      expect(r.salioBien, isTrue, reason: r.problema);
      expect(r.puntos, 60);

      final vuelto = RegistroDeViajes(otro).ultimos(5).single;
      expect(vuelto.inicio, original.inicio);
      expect(vuelto.fin, original.fin);
      expect(vuelto.odoTableroIni, original.odoTableroIni);
      expect(vuelto.odoTableroFin, original.odoTableroFin);
      // Los kilómetros se RECALCULAN desde las muestras, no se copian.
      expect(vuelto.metros, closeTo(original.metros, 1.0));
      expect(vuelto.cortes, original.cortes);
      expect(RegistroDeViajes(otro).puntosDe(vuelto.id), hasLength(60));
      otro.cerrar();
    });

    test('un viaje que ya está no entra dos veces', () async {
      sembrarViaje(base, inicio: 1758489000000);
      await armarServicio(base, nube).subirRecorridos();
      final bajada = await Subida(cliente: nube).bajarRecorrido(
        credencial: credencial,
        id: nube.documentos.keys.first.split('/').last,
      );

      final r = meterViajeDeLaNube(
        viva: base,
        recorrido: bajada.texto!,
        ficha: bajada.ficha,
      );
      expect(r.yaEstaba, isTrue);
      expect(RegistroDeViajes(base).ultimos(10), hasLength(1));
    });

    test('un recorrido ilegible NO deja un viaje a medio armar', () {
      /* Sería lo peor que podría pasar: un viaje con la mitad de sus puntos
         se ve igual que uno entero y dice kilómetros de menos. */
      final r = meterViajeDeLaNube(
        viva: base,
        recorrido: 'no soy un recorrido',
      );
      expect(r.salioBien, isFalse);
      expect(RegistroDeViajes(base).ultimos(10), isEmpty);
      expect(base.db.select('SELECT COUNT(*) AS n FROM puntos').first['n'], 0);
    });

    test('sin ficha se trae igual, con lo que se puede deducir', () async {
      /* Un recorrido subido antes de que la ficha existiera. El viaje entra,
         los kilómetros se calculan, y lo que falta es el odómetro. */
      sembrarViaje(base, inicio: 1758489000000, puntos: 30);
      await armarServicio(base, nube).subirRecorridos();
      final bajada = await Subida(cliente: nube).bajarRecorrido(
        credencial: credencial,
        id: nube.documentos.keys.first.split('/').last,
      );

      final otro = Base.abrir(':memory:');
      final r = meterViajeDeLaNube(viva: otro, recorrido: bajada.texto!);
      expect(r.salioBien, isTrue, reason: r.problema);
      final v = RegistroDeViajes(otro).ultimos(5).single;
      expect(v.inicio, 1758489000000, reason: 'sale del primer punto');
      expect(v.metros, greaterThan(0));
      expect(v.odoTableroIni, isNull);
      otro.cerrar();
    });

    test('un documento que no está se dice, no explota', () async {
      final b = await Subida(cliente: nube)
          .bajarRecorrido(credencial: credencial, id: 'no-existe');
      expect(b.noEstaba, isTrue);
      expect(b.falla, isNull);
    });

    test(
      'si las reglas no dejan leer, el mensaje manda a mirar las reglas',
      () async {
        nube.dejaLeer = false;
        final b = await Subida(cliente: nube)
            .bajarRecorrido(credencial: credencial, id: 'x');
        expect(b.hay, isFalse);
        expect(b.falla, contains('reglas'));
        expect(b.esCulpaNuestra, isTrue);
      },
    );
  });

  group('listar lo que hay arriba', () {
    test('trae el instante y la cantidad, ordenado del más nuevo', () async {
      sembrarViaje(base, inicio: 1000000, puntos: 10);
      sembrarViaje(base, inicio: 3000000, puntos: 20);
      sembrarViaje(base, inicio: 2000000, puntos: 15);
      await armarServicio(base, nube).subirRecorridos();

      final lista = await Subida(cliente: nube)
          .listarRecorridos(credencial: credencial);
      expect(lista.map((r) => r.inicio), [3000000, 2000000, 1000000]);
      expect(lista.map((r) => r.puntos), [20, 15, 10]);
    });

    test('NO se baja el recorrido para listar', () async {
      /* Son cien kilobytes por viaje, y para elegir uno de una lista no hace
         falta ninguno. */
      sembrarViaje(base, inicio: 1000000);
      await armarServicio(base, nube).subirRecorridos();
      nube.urls.clear();
      await Subida(cliente: nube).listarRecorridos(credencial: credencial);
      final listado = nube.urls.firstWhere(
        (u) => u.path.endsWith('recorridos'),
      );
      expect(listado.query, contains('mask.fieldPaths=inicio'));
      expect(listado.query, isNot(contains('datos')));
    });
  });

  group('lo que no se puede romper', () {
    test('el recorrido NO se mete en la colección de reportes', () async {
      /* `reportes/` tiene una propiedad comprobada con una prueba que busca
         coordenadas en su texto. El recorrido va a su propia colección para
         que esa propiedad siga siendo cierta. */
      sembrarViaje(base, inicio: 1000000);
      await armarServicio(base, nube).subirRecorridos();
      for (final clave in nube.documentos.keys) {
        expect(clave, startsWith('recorridos/'));
      }
    });

    test('la contraseña no viaja en la escritura, sólo en el login', () async {
      sembrarViaje(base, inicio: 1000000);
      await armarServicio(base, nube).subirRecorridos();
      final escrito = jsonEncode(nube.documentos);
      expect(escrito, isNot(contains(credencial.clave)));
    });
  });
}
