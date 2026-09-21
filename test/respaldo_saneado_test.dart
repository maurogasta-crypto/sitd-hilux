import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/sesion.dart';
import 'package:sitd_hilux/features/respaldo/saneado.dart';

/// Valores INVENTADOS. No son credenciales de nada: sirven para que la prueba
/// pueda buscarlos en el archivo y fallar si siguen ahí.
const String _claveFalsa = 'contrasena-de-mentira-2026';
const String _tokenFalso = 'refresh-de-mentira-2026';

String get _configFalsa =>
    '{"proyecto":"proyecto-de-mentira","apiKey":"apikey-de-mentira",'
    '"mail":"nadie@ejemplo.invalido","clave":"$_claveFalsa"}';

/// Una base de verdad, en un archivo de verdad: en `:memory:` no hay bytes que
/// mirar, y los bytes son justamente lo que esta prueba comprueba.
({Base base, String ruta, Directory dir}) _baseEnDisco() {
  final dir = Directory.systemTemp.createTempSync('sitd-saneado');
  final ruta = '${dir.path}/sitd.db';
  final base = Base.abrir(ruta);
  base.escribirAjuste(claveDeLaCredencial, _configFalsa);
  base.escribirAjuste(claveDeLaSesion, _tokenFalso);
  base.escribirAjuste('modo_gps_que_anduvo', 'sinNotificacion');
  base.db.execute(
    'INSERT INTO viajes (inicio, fin, metros, metros_haversine) '
    'VALUES (1, 2, 1234.5, 1240.0)',
  );
  return (base: base, ruta: ruta, dir: dir);
}

String _copiar(String ruta, Directory dir) {
  final destino = '${dir.path}/copia.db';
  File(ruta).copySync(destino);
  return destino;
}

void main() {
  group('saneado del respaldo', () {
    test('la copia cruda TRAE la credencial: es el error que se arregla', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      b.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final copia = _copiar(b.ruta, b.dir);

      // Si esto empieza a fallar, la credencial dejó de guardarse en la base y
      // este archivo entero puede revisarse de nuevo.
      expect(
        loQueSeEscapa(copia, [_claveFalsa]),
        _claveFalsa,
        reason:
            'una copia sin sanear tiene que traer la contraseña; si no, '
            'la prueba de abajo no estaría comprobando nada',
      );
    });

    test('sanear saca las dos claves y deja el resto', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      b.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final copia = _copiar(b.ruta, b.dir);

      final sacadas = sanearCopia(copia);
      expect(sacadas, containsAll([claveDeLaCredencial, claveDeLaSesion]));

      final revisada = Base.abrir(copia);
      addTearDown(revisada.cerrar);
      expect(revisada.leerAjuste(claveDeLaCredencial), isNull);
      expect(revisada.leerAjuste(claveDeLaSesion), isNull);
      // Lo que no abre nada se queda: el respaldo tiene que seguir sirviendo.
      expect(revisada.leerAjuste('modo_gps_que_anduvo'), 'sinNotificacion');
      expect(revisada.db.select('SELECT * FROM viajes'), hasLength(1));
    });

    test('y no quedan en los BYTES, que es lo que un DELETE no garantiza', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      b.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final copia = _copiar(b.ruta, b.dir);

      sanearCopia(copia);

      // Ésta es la prueba que falla si alguien saca el VACUUM: la consulta
      // diría que está limpio y el archivo seguiría trayendo el texto.
      expect(
        loQueSeEscapa(copia, [_claveFalsa, _tokenFalso, _configFalsa]),
        isNull,
      );
      // Y ningún `-wal` al lado con lo viejo adentro.
      expect(File('$copia-wal').existsSync(), isFalse);
    });

    test('valoresQueNoSalen trae lo guardado y la contraseña suelta', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      final valores = valoresQueNoSalen(b.base);
      expect(valores, contains(_configFalsa));
      expect(valores, contains(_tokenFalso));
      expect(valores, contains(_claveFalsa));
    });

    test('sanear una base sin nada configurado no rompe ni saca nada', () {
      final dir = Directory.systemTemp.createTempSync('sitd-saneado-vacio');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ruta = '${dir.path}/sitd.db';
      final base = Base.abrir(ruta);
      base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      base.cerrar();

      expect(sanearCopia(ruta), isEmpty);
      expect(loQueSeEscapa(ruta, const []), isNull);
    });

    test('sanear dos veces es inocuo', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      b.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final copia = _copiar(b.ruta, b.dir);

      expect(sanearCopia(copia), isNotEmpty);
      expect(sanearCopia(copia), isEmpty);
    });

    test('cualquier clave que empiece con nube_ también se va', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      // La credencial de mañana, que nadie se acordó de agregar a la lista.
      b.base.escribirAjuste('nube_lo_que_venga', 'secreto-de-mentira-2026');
      b.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final copia = _copiar(b.ruta, b.dir);

      expect(sanearCopia(copia), contains('nube_lo_que_venga'));
      expect(loQueSeEscapa(copia, ['secreto-de-mentira-2026']), isNull);
    });

    test('la base VIVA no se toca: sanear es siempre sobre una copia', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      b.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final copia = _copiar(b.ruta, b.dir);
      sanearCopia(copia);

      // Si se saneara la viva, el teléfono dejaría de poder subir reportes
      // después de cada respaldo, y eso no se nota hasta el viaje siguiente.
      expect(b.base.leerAjuste(claveDeLaCredencial), _configFalsa);
      expect(b.base.leerAjuste(claveDeLaSesion), _tokenFalso);
    });

    test('las dos claves selladas son las que usan sus guardas', () {
      final b = _baseEnDisco();
      addTearDown(() {
        b.base.cerrar();
        b.dir.deleteSync(recursive: true);
      });
      // No es tautología: comprueba que la constante pública y la que el
      // guarda escribe de verdad son la misma. Si alguien cambia una sola, el
      // saneado dejaría de encontrar la credencial y nadie se enteraría.
      expect(GuardaDeSesion(b.base).token, _tokenFalso);
      expect(GuardaDeCredencial(b.base).credencial?.clave, _claveFalsa);
      expect(clavesQueNoSalen, [claveDeLaCredencial, claveDeLaSesion]);
    });
  });
}
