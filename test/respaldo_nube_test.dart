import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/nube/cola.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/respaldo_nube.dart';
import 'package:sitd_hilux/features/nube/servicio_nube.dart';
import 'package:sitd_hilux/features/nube/sesion.dart';
import 'package:sitd_hilux/features/nube/subida.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/respaldo/importar.dart';

import 'recorrido_nube_test.dart'
    show NubeFalsa, credencial, credencialPegada, sembrarViaje;

/// El respaldo COMPLETO en la nube (`sitd-34`).
///
/// Lo que se cuida acá, en orden de cuánto cuesta equivocarlo:
///
/// 1. que la contraseña y la sesión **no suban**, buscadas en los bytes que
///    efectivamente llegaron a la nube y no en la copia local;
/// 2. que un respaldo cortado a mitad de camino **no aparezca** en la lista;
/// 3. que una parte cambiada, cortada o que falta **se diga**, y no termine en
///    una base rota metida en el teléfono;
/// 4. que la vuelta entera —un teléfono sube, otro vacío baja y suma— deje en
///    el segundo lo mismo que tenía el primero.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sitd-respaldo-nube'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Una base en disco —en `:memory:` no hay archivo que subir— con dos
  /// viajes, la credencial y un token de sesión guardados.
  ({Base base, String ruta}) telefonoConDatos(String nombre) {
    final ruta = '${dir.path}/$nombre.db';
    final base = Base.abrir(ruta);
    GuardaDeCredencial(base).guardar(credencialPegada);
    GuardaDeSesion(base).guardar('refresh-de-mentira-para-el-banco');
    sembrarViaje(base, inicio: 1758489000000, puntos: 300);
    sembrarViaje(base, inicio: 1758575400000, puntos: 200);
    return (base: base, ruta: ruta);
  }

  ServicioNube servicio(Base base, NubeFalsa nube) => ServicioNube(
    cola: ColaDeSubida(base),
    guarda: GuardaDeCredencial(base)..guardar(credencialPegada),
    subida: Subida(cliente: nube),
    armar: (v) => {'viajes': []},
    viajes: RegistroDeViajes(base),
  );

  Uint8List bytesDeUnaBase() {
    final t = telefonoConDatos('suelta');
    t.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    t.base.cerrar();
    return File(t.ruta).readAsBytesSync();
  }

  group('empacar y desempacar', () {
    test('la vuelta devuelve EXACTAMENTE los mismos bytes', () {
      final base = bytesDeUnaBase();
      final e = empacar(base, porParte: 1000);
      expect(e.partes.length, greaterThan(3), reason: 'tiene que partir');
      final vuelta = desempacar(
        e.partes,
        bytesOriginal: e.bytesOriginal,
        bytesComprimido: e.bytesComprimido,
      );
      expect(vuelta, base);
    });

    test('ninguna parte pasa del tope, y juntas son el comprimido', () {
      final e = empacar(bytesDeUnaBase(), porParte: 1000);
      for (final p in e.partes.take(e.partes.length - 1)) {
        expect(p.length, 1000);
      }
      expect(e.partes.last.length, inInclusiveRange(1, 1000));
      expect(e.partes.fold<int>(0, (s, p) => s + p.length), e.bytesComprimido);
    });

    test('comprime: una base de SQLite tiene mucho espacio repetido', () {
      final e = empacar(bytesDeUnaBase());
      expect(e.bytesComprimido, lessThan(e.bytesOriginal ~/ 2));
      expect(e.partes, hasLength(1));
    });

    test('lo que no es una base no se empaca', () {
      expect(
        () => empacar(Uint8List.fromList(utf8.encode('hola, no soy una base'))),
        throwsFormatException,
      );
    });

    test('más partes que el techo se dice ANTES de subir nada', () {
      expect(
        () => empacar(bytesDeUnaBase(), porParte: 10),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'mensaje',
            contains('$maximoDePartes'),
          ),
        ),
      );
    });

    group('cada forma de romperse tiene su frase', () {
      late Empaque e;
      setUp(() => e = empacar(bytesDeUnaBase(), porParte: 1000));

      Matcher dice(String algo) => throwsA(
        isA<FormatException>().having(
          (x) => x.message,
          'mensaje',
          contains(algo),
        ),
      );

      test('falta una parte', () {
        final partes = List<Uint8List?>.of(e.partes)..[2] = null;
        expect(
          () => desempacar(
            partes,
            bytesOriginal: e.bytesOriginal,
            bytesComprimido: e.bytesComprimido,
          ),
          dice('Faltan 1 de ${e.partes.length}'),
        );
      });

      test('una parte llegó cortada', () {
        final partes = List<Uint8List?>.of(e.partes)
          ..[1] = Uint8List.sublistView(e.partes[1], 0, 500);
        expect(
          () => desempacar(
            partes,
            bytesOriginal: e.bytesOriginal,
            bytesComprimido: e.bytesComprimido,
          ),
          dice('alguna llegó cortada'),
        );
      });

      test('una parte llegó CAMBIADA, del mismo largo', () {
        // Es el caso que un control de largos no ve, y el que el CRC de gzip
        // está para agarrar.
        final cambiada = Uint8List.fromList(e.partes[2]);
        cambiada[400] ^= 0xFF;
        final partes = List<Uint8List?>.of(e.partes)..[2] = cambiada;
        expect(
          () => desempacar(
            partes,
            bytesOriginal: e.bytesOriginal,
            bytesComprimido: e.bytesComprimido,
          ),
          dice('llegó cambiada'),
        );
      });

      test('el manifiesto promete otro largo', () {
        expect(
          () => desempacar(
            e.partes,
            bytesOriginal: e.bytesOriginal + 1,
            bytesComprimido: e.bytesComprimido,
          ),
          dice('Descomprimido mide'),
        );
      });

      test('sin partes', () {
        expect(
          () => desempacar(const [], bytesOriginal: 1, bytesComprimido: 1),
          dice('ninguna parte'),
        );
      });

      test('descomprime bien pero no es una base', () {
        final texto = Uint8List.fromList(utf8.encode('no soy una base' * 50));
        final comprimido = Uint8List.fromList(gzip.encode(texto));
        expect(
          () => desempacar(
            [comprimido],
            bytesOriginal: texto.length,
            bytesComprimido: comprimido.length,
          ),
          dice('no es una base'),
        );
      });
    });
  });

  group('el formato de Firestore', () {
    const m = RespaldoEnLaNube(
      id: 'telefono-r1758489000000',
      creado: 1758489000000,
      sello: 'sitd-34',
      esquema: 6,
      bytesOriginal: 4194304,
      bytesComprimido: 1048000,
      partes: 2,
      resumen: '2 viajes, 500 puntos, 0 cargas',
    );

    test('el manifiesto lleva exactamente sus campos', () {
      expect(m.campos.keys.toList(), camposDelManifiesto);
    });

    test('ida y vuelta, con los enteros como texto como los da Firestore', () {
      final r = RespaldoEnLaNube.desdeFirestore(m.id, m.campos)!;
      expect(r.creado, m.creado);
      expect(r.sello, m.sello);
      expect(r.esquema, m.esquema);
      expect(r.bytesOriginal, m.bytesOriginal);
      expect(r.bytesComprimido, m.bytesComprimido);
      expect(r.partes, m.partes);
      expect(r.resumen, m.resumen);
    });

    test('un manifiesto a medias no se ofrece', () {
      for (final falta in [
        'creado',
        'bytesOriginal',
        'bytesComprimido',
        'partes',
      ]) {
        final campos = Map.of(m.campos)..remove(falta);
        expect(
          RespaldoEnLaNube.desdeFirestore(m.id, campos),
          isNull,
          reason: 'sin $falta',
        );
      }
      final cero = Map.of(m.campos)..['partes'] = {'integerValue': '0'};
      expect(RespaldoEnLaNube.desdeFirestore(m.id, cero), isNull);
    });

    test('una parte lleva sus campos y los bytes vuelven iguales', () {
      final datos = Uint8List.fromList([0, 1, 2, 250, 255, 43, 47]);
      final campos = camposDeParte(3, datos);
      expect(campos.keys.toList(), camposDeUnaParte);
      expect(datosDeParte(campos), datos);
      expect(
        datosDeParte({
          'datos': {'bytesValue': '%%%'},
        }),
        isNull,
      );
    });

    test('el nombre de una parte se ordena en la consola', () {
      expect(nombreDeParte(0), 'p000');
      expect(nombreDeParte(7), 'p007');
      expect(nombreDeParte(39), 'p039');
    });
  });

  group('de un teléfono a otro, por la nube', () {
    test(
      'sube, y lo que llegó arriba NO trae la contraseña ni la sesión',
      () async {
        final a = telefonoConDatos('a');
        final nube = NubeFalsa();
        final r = await servicio(a.base, nube).subirRespaldoCompleto(
          base: a.base,
          ruta: a.ruta,
          carpeta: dir.path,
          porParte: 4000,
          ahora: 1759000000000,
        );
        expect(r.resultado.ok, isTrue, reason: r.resultado.falla);
        final m = r.manifiesto!;
        expect(m.partes, greaterThan(1));
        expect(m.resumen, contains('2 viajes'));

        // Se busca en lo que LLEGÓ, rearmado desde los documentos de la nube.
        final partes = [
          for (var i = 0; i < m.partes; i++)
            datosDeParte(
              nube.documentos['respaldos/${m.id}/partes/${nombreDeParte(i)}'],
            ),
        ];
        final arriba = desempacar(
          partes,
          bytesOriginal: m.bytesOriginal,
          bytesComprimido: m.bytesComprimido,
        );
        final texto = latin1.decode(arriba);
        expect(texto, isNot(contains(credencial.clave)));
        expect(texto, isNot(contains('refresh-de-mentira-para-el-banco')));
        expect(texto, isNot(contains(credencial.apiKey)));
        a.base.cerrar();
      },
    );

    test('las partes van PRIMERO y el manifiesto AL FINAL', () async {
      final a = telefonoConDatos('a');
      final nube = NubeFalsa();
      await servicio(a.base, nube).subirRespaldoCompleto(
        base: a.base,
        ruta: a.ruta,
        carpeta: dir.path,
        porParte: 4000,
      );
      final escrituras = [
        for (final u in nube.urls)
          if (u.queryParameters.containsKey('documentId')) u,
      ];
      expect(escrituras.last.path, endsWith('/documents/respaldos'));
      for (final u in escrituras.take(escrituras.length - 1)) {
        expect(u.path, endsWith('/partes'));
      }
      a.base.cerrar();
    });

    test(
      'cortado a mitad de camino: no hay manifiesto y la lista no lo muestra',
      () async {
        final a = telefonoConDatos('a');
        final nube = NubeFalsa()..cortarDespuesDe = 2;
        final s = servicio(a.base, nube);
        final r = await s.subirRespaldoCompleto(
          base: a.base,
          ruta: a.ruta,
          carpeta: dir.path,
          porParte: 4000,
        );
        expect(r.resultado.ok, isFalse);
        expect(r.resultado.falla, contains('La parte 3 de'));
        // No es culpa nuestra: es la red, y se puede volver a intentar.
        expect(r.resultado.esCulpaNuestra, isFalse);
        expect(r.manifiesto, isNull);
        expect(
          nube.documentos.keys.where((k) => !k.contains('/partes/')),
          isEmpty,
          reason:
              'un manifiesto sin sus partes sería un respaldo roto a la vista',
        );
        final lista = await s.subida.listarRespaldos(credencial: credencial);
        expect(lista.lista, isEmpty);
        expect(lista.falla, isNull);
        a.base.cerrar();
      },
    );

    test(
      'la copia de trabajo no queda en el teléfono, salga bien o mal',
      () async {
        final a = telefonoConDatos('a');
        final trabajo = Directory('${dir.path}/trabajo')..createSync();
        await servicio(a.base, NubeFalsa()).subirRespaldoCompleto(
          base: a.base,
          ruta: a.ruta,
          carpeta: trabajo.path,
        );
        await servicio(
          a.base,
          NubeFalsa()..cortarDespuesDe = 0,
        ).subirRespaldoCompleto(
          base: a.base,
          ruta: a.ruta,
          carpeta: trabajo.path,
        );
        expect(trabajo.listSync(), isEmpty);
        a.base.cerrar();
      },
    );

    test(
      'sin las reglas publicadas, se DICE, y no parece una lista vacía',
      () async {
        final a = telefonoConDatos('a');
        final nube = NubeFalsa()..negadas.add('respaldos');
        final s = servicio(a.base, nube);
        final lista = await s.subida.listarRespaldos(credencial: credencial);
        expect(lista.lista, isEmpty);
        expect(lista.falla, contains('respaldos'));
        expect(lista.falla, contains('firestore.rules'));

        final r = await s.subirRespaldoCompleto(
          base: a.base,
          ruta: a.ruta,
          carpeta: dir.path,
        );
        expect(r.resultado.ok, isFalse);
        expect(r.resultado.esCulpaNuestra, isTrue);
        a.base.cerrar();
      },
    );

    test('otro teléfono VACÍO lo baja, lo suma y queda con lo mismo', () async {
      final a = telefonoConDatos('a');
      final nube = NubeFalsa();
      await servicio(a.base, nube).subirRespaldoCompleto(
        base: a.base,
        ruta: a.ruta,
        carpeta: dir.path,
        porParte: 4000,
      );

      final b = Base.abrir('${dir.path}/b.db');
      final sb = servicio(b, nube);
      final lista = await sb.subida.listarRespaldos(credencial: credencial);
      expect(lista.lista, hasLength(1));
      final bajado = await sb.bajarRespaldoCompleto(
        respaldo: lista.lista.single,
        carpeta: dir.path,
      );
      expect(bajado.falla, isNull);

      final revision = revisarRespaldo(viva: b, ruta: bajado.ruta!);
      expect(revision.sePuede, isTrue, reason: revision.problema);
      expect(revision.viajesNuevos, 2);

      final sumado = sumarRespaldo(
        viva: b,
        ruta: bajado.ruta!,
        carpetaDeTrabajo: dir.path,
      );
      expect(sumado.salioBien, isTrue, reason: sumado.problema);

      int cuantos(Base x, String t) =>
          x.db.select('SELECT COUNT(*) AS n FROM $t').first['n'] as int;
      for (final t in ['viajes', 'puntos']) {
        expect(cuantos(b, t), cuantos(a.base, t), reason: t);
      }
      // Y el teléfono B sigue con SU credencial: la del respaldo no viaja.
      expect(GuardaDeCredencial(b).credencial?.proyecto, credencial.proyecto);
      a.base.cerrar();
      b.cerrar();
    });

    test(
      'si arriba falta una parte, bajar lo dice y no deja archivo',
      () async {
        final a = telefonoConDatos('a');
        final nube = NubeFalsa();
        final r = await servicio(a.base, nube).subirRespaldoCompleto(
          base: a.base,
          ruta: a.ruta,
          carpeta: dir.path,
          porParte: 4000,
        );
        final m = r.manifiesto!;
        nube.documentos.remove('respaldos/${m.id}/partes/${nombreDeParte(1)}');
        final trabajo = Directory('${dir.path}/bajadas')..createSync();
        final b = await servicio(
          a.base,
          nube,
        ).bajarRespaldoCompleto(respaldo: m, carpeta: trabajo.path);
        expect(b.ruta, isNull);
        expect(b.falla, contains('Faltan 1 de ${m.partes}'));
        expect(trabajo.listSync(), isEmpty);
        a.base.cerrar();
      },
    );
  });
}
