import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/core/db/esquema.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/respaldo/importar.dart';

/// Un viaje de mentira, para que las dos bases tengan algo distinto adentro.
void sembrar(Base base, {required int viajes, required int puntosPorViaje}) {
  final r = RegistroDeViajes(base);
  for (var v = 0; v < viajes; v++) {
    final id = r.abrir(inicio: v * 100000, odoTablero: 1000 + v * 100);
    for (var i = 0; i < puntosPorViaje; i++) {
      r.guardarPunto(
        id,
        Muestra(
          t: v * 100000 + i * 1000,
          lat: -34.9,
          lon: -56.2,
          velocidad: 20,
          precision: 5,
        ),
      );
    }
    r.recalcular(id);
    r.cerrar(
      id,
      fin: v * 100000 + puntosPorViaje * 1000,
      odoTablero: 1050 + v * 100,
    );
  }
}

void main() {
  late Directory dir;
  late Base viva;
  late String rutaViva;
  late String rutaRespaldo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sitd-importar');
    rutaViva = '${dir.path}/sitd.db';
    rutaRespaldo = '${dir.path}/respaldo.db';
    viva = Base.abrir(rutaViva);
  });

  tearDown(() {
    viva.cerrar();
    dir.deleteSync(recursive: true);
  });

  /// Arma un archivo de respaldo con su propio contenido.
  void respaldoCon({required int viajes, required int puntos}) {
    final otra = Base.abrir(rutaRespaldo);
    sembrar(otra, viajes: viajes, puntosPorViaje: puntos);
    otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    otra.cerrar();
  }

  group('mirar antes de tocar', () {
    test('dice qué hay de los dos lados, sin cambiar nada', () {
      sembrar(viva, viajes: 1, puntosPorViaje: 10);
      respaldoCon(viajes: 3, puntos: 20);

      final r = revisarRespaldo(viva: viva, ruta: rutaRespaldo);
      expect(r.sePuede, isTrue);
      expect(r.actual.viajes, 1);
      expect(r.candidato!.viajes, 3);
      expect(r.candidato!.puntos, 60);
      // Mirar no toca: la base viva sigue con lo suyo.
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(1));
    });

    test('un archivo que no está se dice, no se explota', () {
      final r = revisarRespaldo(viva: viva, ruta: '${dir.path}/no-existe.db');
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('no está'));
    });

    test('un archivo que no es una base tampoco', () {
      final basura = File('${dir.path}/basura.db')
        ..writeAsStringSync('esto no es sqlite');
      final r = revisarRespaldo(viva: viva, ruta: basura.path);
      expect(r.sePuede, isFalse);
    });

    test('una base de OTRA aplicación se reconoce y se rechaza', () {
      final otra = Base.abrir('${dir.path}/ajena.db');
      otra.db.execute('DROP TABLE viajes');
      otra.cerrar();
      final r = revisarRespaldo(viva: viva, ruta: '${dir.path}/ajena.db');
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('no de esta'));
    });

    test('un respaldo MÁS NUEVO que la aplicación no se importa', () {
      /* Es la que más importa de este grupo: lo que la aplicación todavía no
         sabe guardar se perdería sin aviso. */
      respaldoCon(viajes: 1, puntos: 5);
      final otra = Base.abrir(rutaRespaldo);
      otra.db.execute('PRAGMA user_version = ${versionEsquema + 1}');
      otra.cerrar();

      final r = revisarRespaldo(viva: viva, ruta: rutaRespaldo);
      expect(r.sePuede, isFalse);
      expect(r.problema, contains('MÁS NUEVA'));
    });
  });

  group('importar', () {
    test('reemplaza la historia entera', () {
      sembrar(viva, viajes: 1, puntosPorViaje: 10);
      respaldoCon(viajes: 3, puntos: 20);

      final problema = importarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(problema, isNull);
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(3));
      expect(revisarRespaldo(viva: viva, ruta: rutaRespaldo).actual.puntos, 60);
    });

    test('la configuración de la nube de ESTE teléfono no se toca', () {
      /* La del archivo puede ser de antes de `sitd-21` y estar rotada. La que
         vale es la que el teléfono tiene ahora. */
      viva.escribirAjuste(claveDeLaCredencial, 'LA-DE-AHORA');
      viva.escribirAjuste('modo_gps_que_anduvo', 'sinNotificacion');
      respaldoCon(viajes: 1, puntos: 5);
      final otra = Base.abrir(rutaRespaldo);
      otra.escribirAjuste(claveDeLaCredencial, 'LA-VIEJA-Y-ROTADA');
      otra.cerrar();

      importarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(viva.leerAjuste(claveDeLaCredencial), 'LA-DE-AHORA');
      expect(viva.leerAjuste('modo_gps_que_anduvo'), 'sinNotificacion');
    });

    test('el archivo de Mauro no se modifica', () {
      respaldoCon(viajes: 2, puntos: 10);
      final antes = File(rutaRespaldo).readAsBytesSync();
      importarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(File(rutaRespaldo).readAsBytesSync(), antes);
    });

    test('no deja temporales dando vueltas', () {
      respaldoCon(viajes: 1, puntos: 5);
      importarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(File('${dir.path}/importando.db').existsSync(), isFalse);
    });

    test('importar dos veces da lo mismo', () {
      respaldoCon(viajes: 2, puntos: 10);
      for (var i = 0; i < 2; i++) {
        expect(
          importarRespaldo(
            viva: viva,
            ruta: rutaRespaldo,
            carpetaDeTrabajo: dir.path,
          ),
          isNull,
        );
      }
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(2));
    });

    test('un respaldo vacío deja la base vacía, y lo dice sin romperse', () {
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      respaldoCon(viajes: 0, puntos: 0);
      expect(
        importarRespaldo(
          viva: viva,
          ruta: rutaRespaldo,
          carpetaDeTrabajo: dir.path,
        ),
        isNull,
      );
      expect(RegistroDeViajes(viva).ultimos(10), isEmpty);
    });

    test('si el archivo no sirve, NO toca la base', () {
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      final basura = File('${dir.path}/basura.db')
        ..writeAsStringSync('no soy sqlite');
      expect(
        importarRespaldo(
          viva: viva,
          ruta: basura.path,
          carpetaDeTrabajo: dir.path,
        ),
        isNotNull,
      );
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(2));
    });
  });

  group('la lista de tablas no se puede olvidar', () {
    test('cubre TODAS las del esquema, salvo las declaradas', () {
      /* Es la misma red que «una colección nueva entra con su regla»: si
         mañana alguien agrega una tabla y no la agrega acá, su contenido no
         viajaría en un respaldo y nadie se enteraría hasta necesitarlo. */
      final b = Base.abrir('${dir.path}/vacia.db');
      final nombres = b.tablas.toSet();
      b.cerrar();

      expect(
        nombres.difference({...tablasQueSeImportan, ...tablasQueNoSeImportan}),
        isEmpty,
        reason:
            'hay una tabla del esquema que no está declarada ni como que se '
            'importa ni como que no',
      );

      // Y al revés: que no se declare una que no existe.
      expect(
        {...tablasQueSeImportan, ...tablasQueNoSeImportan}.difference(nombres),
        isEmpty,
        reason: 'se declara una tabla que el esquema no tiene',
      );
    });

    test('`viajes` va primero: las otras lo referencian', () {
      expect(tablasQueSeImportan.first, 'viajes');
    });

    test('`ajustes` NO viaja: es la configuración de este teléfono', () {
      expect(tablasQueNoSeImportan, contains('ajustes'));
      expect(tablasQueSeImportan, isNot(contains('ajustes')));
    });
  });
}
