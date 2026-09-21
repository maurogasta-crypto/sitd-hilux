import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/core/db/esquema.dart';
import 'package:sitd_hilux/features/combustible/carga.dart';
import 'package:sitd_hilux/features/combustible/registro_cargas.dart';
import 'package:sitd_hilux/features/nube/cola.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/respaldo/importar.dart';

/// Un viaje de mentira, para que las dos bases tengan algo distinto adentro.
///
/// [desde] corre el instante de arranque de los viajes. **Es lo que distingue
/// un juego de viajes de otro**: la suma reconoce un viaje repetido por su
/// `inicio`, así que dos `sembrar` con el mismo [desde] son, a propósito, el
/// mismo viaje dos veces.
void sembrar(
  Base base, {
  required int viajes,
  required int puntosPorViaje,
  int desde = 0,
}) {
  final r = RegistroDeViajes(base);
  for (var v = 0; v < viajes; v++) {
    final arranque = desde + v * 100000;
    final id = r.abrir(inicio: arranque, odoTablero: 1000 + v * 100);
    for (var i = 0; i < puntosPorViaje; i++) {
      r.guardarPunto(
        id,
        Muestra(
          t: arranque + i * 1000,
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
      fin: arranque + puntosPorViaje * 1000,
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
  void respaldoCon({required int viajes, required int puntos, int desde = 0}) {
    final otra = Base.abrir(rutaRespaldo);
    sembrar(otra, viajes: viajes, puntosPorViaje: puntos, desde: desde);
    otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    otra.cerrar();
  }

  /// Un instante bien lejos del de la base viva, para que nada se confunda.
  const otraNoche = 900000000;

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

    test('dice cuántos viajes entrarían si se suma', () {
      /* Es el número con el que el cartel le promete algo a Mauro: si acá
         dijera una cosa y la suma hiciera otra, la promesa sería falsa. */
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      respaldoCon(viajes: 3, puntos: 20, desde: otraNoche);

      final r = revisarRespaldo(viva: viva, ruta: rutaRespaldo);
      expect(r.viajesNuevos, 3);
      expect(r.viajesRepetidos, 0);
      expect(r.sumarTraeAlgo, isTrue);
      expect(r.viajesDespuesDeSumar, 5);
    });

    test('y lo que promete es EXACTAMENTE lo que después entra', () {
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      // Dos que ya están y dos que no: el caso mezclado, que es el difícil.
      respaldoCon(viajes: 2, puntos: 10);
      final otra = Base.abrir(rutaRespaldo);
      sembrar(otra, viajes: 2, puntosPorViaje: 10, desde: otraNoche);
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      final prometido = revisarRespaldo(viva: viva, ruta: rutaRespaldo);
      expect(prometido.viajesNuevos, 2);
      expect(prometido.viajesRepetidos, 2);

      final hecho = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(hecho.viajes, prometido.viajesNuevos);
      expect(hecho.viajesRepetidos, prometido.viajesRepetidos);
      expect(
        RegistroDeViajes(viva).ultimos(10),
        hasLength(prometido.viajesDespuesDeSumar),
      );
    });

    test('si todos los viajes ya están, avisa que sumar no trae nada', () {
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      respaldoCon(viajes: 2, puntos: 10);

      final r = revisarRespaldo(viva: viva, ruta: rutaRespaldo);
      expect(r.sePuede, isTrue);
      expect(r.viajesNuevos, 0);
      expect(r.viajesRepetidos, 2);
      expect(r.sumarTraeAlgo, isFalse);
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

  group('sumar', () {
    test('junta los dos juegos y no pierde ninguno', () {
      /* ── ES EL CASO DEL 2026-09-21, Y ES EL MOTIVO DE ESTA UNIDAD ───────
         Mauro tenía dos viajes de esa noche en el teléfono y dos de la
         anterior en un archivo. Ninguno de los dos juegos contenía al otro, y
         la única herramienta que había —reemplazar— le hacía elegir cuál
         perder. */
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      respaldoCon(viajes: 2, puntos: 20, desde: otraNoche);

      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.salioBien, isTrue, reason: r.problema);
      expect(r.viajes, 2);
      expect(r.viajesRepetidos, 0);
      expect(r.puntos, 40);
      // Los cuatro, los dos que estaban y los dos que entraron.
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(4));
      expect(revisarRespaldo(viva: viva, ruta: rutaRespaldo).actual.puntos, 60);
    });

    test('cada punto queda colgado de SU viaje, aunque el número cambie', () {
      /* El corazón de la suma: las dos bases numeran desde uno, así que el
         viaje 1 del archivo no es el viaje 1 del teléfono. Si la traducción
         del número fallara, los puntos de un viaje aparecerían en otro y los
         kilómetros de los dos quedarían mal SIN DAR ERROR. */
      sembrar(viva, viajes: 2, puntosPorViaje: 7);
      respaldoCon(viajes: 3, puntos: 13, desde: otraNoche);

      sumarRespaldo(viva: viva, ruta: rutaRespaldo, carpetaDeTrabajo: dir.path);

      final registro = RegistroDeViajes(viva);
      final viajes = registro.ultimos(10);
      expect(viajes, hasLength(5));
      for (final v in viajes) {
        // Cada viaje tiene los suyos y sólo los suyos.
        final esperados = v.inicio >= otraNoche ? 13 : 7;
        expect(
          registro.puntosDe(v.id),
          hasLength(esperados),
          reason: 'el viaje ${v.id} quedó con los puntos de otro',
        );
      }
      // Y ninguno quedó apuntando a un viaje que no existe.
      expect(
        viva.db
            .select(
              'SELECT COUNT(*) AS n FROM puntos '
              'WHERE viaje NOT IN (SELECT id FROM viajes)',
            )
            .first['n'],
        0,
      );
    });

    test('sumar dos veces el mismo archivo no duplica nada', () {
      /* La propiedad que lo hace usable sin miedo: si uno no se acuerda de si
         ya lo metió, lo vuelve a meter y no pasa nada. */
      sembrar(viva, viajes: 1, puntosPorViaje: 5);
      respaldoCon(viajes: 2, puntos: 10, desde: otraNoche);

      final primera = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      final segunda = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );

      expect(primera.viajes, 2);
      expect(segunda.viajes, 0);
      expect(segunda.viajesRepetidos, 2);
      expect(segunda.nadaNuevo, isTrue);
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(3));
      expect(revisarRespaldo(viva: viva, ruta: rutaRespaldo).actual.puntos, 25);
    });

    test('ante un viaje repetido gana el del teléfono, no el del archivo', () {
      /* Es lo conservador: el archivo es viejo por definición, y lo que está
         vivo puede haberse corregido después. */
      sembrar(viva, viajes: 1, puntosPorViaje: 5);
      viva.db.execute("UPDATE viajes SET notas = 'la corregida a mano'");
      respaldoCon(viajes: 1, puntos: 5);
      final otra = Base.abrir(rutaRespaldo);
      otra.db.execute("UPDATE viajes SET notas = 'la vieja del archivo'");
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.viajesRepetidos, 1);
      expect(r.viajes, 0);
      expect(
        viva.db.select('SELECT notas FROM viajes').single['notas'],
        'la corregida a mano',
      );
    });

    test('la cola de subida viaja con su viaje, apuntada al número nuevo', () {
      /* `subidas` tiene al viaje como clave primaria, así que si la traducción
         no la alcanzara, la fila entraría apuntando a un viaje del OTRO juego
         y un viaje ya subido se volvería a subir, o al revés. */
      sembrar(viva, viajes: 1, puntosPorViaje: 5);
      respaldoCon(viajes: 1, puntos: 5, desde: otraNoche);
      final otra = Base.abrir(rutaRespaldo);
      ColaDeSubida(otra).encolar(RegistroDeViajes(otra).ultimos(1).single.id);
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      sumarRespaldo(viva: viva, ruta: rutaRespaldo, carpetaDeTrabajo: dir.path);

      final elQueEntro = RegistroDeViajes(viva)
          .ultimos(10)
          .firstWhere((v) => v.inicio >= otraNoche);
      expect(ColaDeSubida(viva).pendientes().map((p) => p.viaje), [
        elQueEntro.id,
      ]);
      expect(
        viva.db
            .select(
              'SELECT COUNT(*) AS n FROM subidas '
              'WHERE viaje NOT IN (SELECT id FROM viajes)',
            )
            .first['n'],
        0,
      );
    });

    test('las cargas se reconocen por su instante y no se duplican', () {
      final carga = Carga(t: 1700000000000, litros: 50, odoTablero: 405000);
      RegistroDeCargas(viva).guardar(carga);
      respaldoCon(viajes: 0, puntos: 0);
      final otra = Base.abrir(rutaRespaldo);
      RegistroDeCargas(otra).guardar(carga); // la MISMA
      RegistroDeCargas(otra).guardar(
        Carga(t: 1700000999000, litros: 30, odoTablero: 405400),
      ); // una nueva
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.cargas, 1);
      expect(r.cargasRepetidas, 1);
      expect(RegistroDeCargas(viva).todas(), hasLength(2));
    });

    test('la bitácora se suma sin repetir la línea que ya estaba', () {
      viva.db.execute(
        "INSERT INTO eventos (t, origen, texto) VALUES (10, 'sistema', 'la misma')",
      );
      respaldoCon(viajes: 0, puntos: 0);
      final otra = Base.abrir(rutaRespaldo);
      otra.db.execute(
        "INSERT INTO eventos (t, origen, texto) VALUES "
        "(10, 'sistema', 'la misma'), (20, 'viaje', 'una nueva')",
      );
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.eventos, 1);
      expect(viva.db.select('SELECT COUNT(*) AS n FROM eventos').first['n'], 2);
    });

    test('dos líneas del mismo milisegundo que dicen cosas distintas entran '
        'las dos', () {
      /* Por eso la llave de `eventos` son los tres campos y no sólo el
         instante: la bitácora escribe varias líneas en el mismo milisegundo
         al arrancar. Con la llave corta, se habría perdido todo menos una. */
      respaldoCon(viajes: 0, puntos: 0);
      final otra = Base.abrir(rutaRespaldo);
      otra.db.execute(
        "INSERT INTO eventos (t, origen, texto) VALUES "
        "(10, 'sistema', 'una'), (10, 'sistema', 'otra')",
      );
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      expect(
        sumarRespaldo(
          viva: viva,
          ruta: rutaRespaldo,
          carpetaDeTrabajo: dir.path,
        ).eventos,
        2,
      );
    });

    test('la configuración de la nube de ESTE teléfono no se toca', () {
      viva.escribirAjuste(claveDeLaCredencial, 'LA-DE-AHORA');
      viva.escribirAjuste('modo_gps_que_anduvo', 'sinNotificacion');
      respaldoCon(viajes: 1, puntos: 5, desde: otraNoche);
      final otra = Base.abrir(rutaRespaldo);
      otra.escribirAjuste(claveDeLaCredencial, 'LA-VIEJA-Y-ROTADA');
      otra.cerrar();

      sumarRespaldo(viva: viva, ruta: rutaRespaldo, carpetaDeTrabajo: dir.path);
      expect(viva.leerAjuste(claveDeLaCredencial), 'LA-DE-AHORA');
      expect(viva.leerAjuste('modo_gps_que_anduvo'), 'sinNotificacion');
    });

    test('el archivo de Mauro no se modifica', () {
      sembrar(viva, viajes: 1, puntosPorViaje: 5);
      respaldoCon(viajes: 2, puntos: 10, desde: otraNoche);
      final antes = File(rutaRespaldo).readAsBytesSync();
      sumarRespaldo(viva: viva, ruta: rutaRespaldo, carpetaDeTrabajo: dir.path);
      expect(File(rutaRespaldo).readAsBytesSync(), antes);
    });

    test('no deja temporales dando vueltas', () {
      respaldoCon(viajes: 1, puntos: 5, desde: otraNoche);
      sumarRespaldo(viva: viva, ruta: rutaRespaldo, carpetaDeTrabajo: dir.path);
      expect(File('${dir.path}/importando.db').existsSync(), isFalse);
    });

    test('si el archivo no sirve, NO toca la base y lo dice', () {
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      final basura = File('${dir.path}/basura.db')
        ..writeAsStringSync('no soy sqlite');
      final r = sumarRespaldo(
        viva: viva,
        ruta: basura.path,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.salioBien, isFalse);
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(2));
      expect(viva.db.select('SELECT COUNT(*) AS n FROM puntos').first['n'], 20);
    });

    test('un respaldo vacío no rompe nada y avisa que no había nada', () {
      sembrar(viva, viajes: 2, puntosPorViaje: 10);
      respaldoCon(viajes: 0, puntos: 0);
      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.salioBien, isTrue);
      expect(r.nadaNuevo, isTrue);
      expect(r.resumen, contains('nada nuevo'));
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(2));
    });

    test('sumar sobre una base vacía deja lo mismo que reemplazar', () {
      /* Con el teléfono recién formateado las dos formas tienen que dar el
         mismo resultado. Si no, una de las dos está mal. */
      respaldoCon(viajes: 3, puntos: 8, desde: otraNoche);
      sumarRespaldo(viva: viva, ruta: rutaRespaldo, carpetaDeTrabajo: dir.path);
      final porSuma = revisarRespaldo(viva: viva, ruta: rutaRespaldo).actual;

      final otraViva = Base.abrir('${dir.path}/otra-viva.db');
      importarRespaldo(
        viva: otraViva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      final porReemplazo = revisarRespaldo(
        viva: otraViva,
        ruta: rutaRespaldo,
      ).actual;
      otraViva.cerrar();

      expect(porSuma.viajes, porReemplazo.viajes);
      expect(porSuma.puntos, porReemplazo.puntos);
      expect(porSuma.vibraciones, porReemplazo.vibraciones);
    });

    test('sumar lo que ya se había REEMPLAZADO no duplica', () {
      /* Las dos formas comparten la llave natural, así que una detrás de la
         otra no puede hacer aparecer un viaje dos veces. */
      respaldoCon(viajes: 2, puntos: 10, desde: otraNoche);
      importarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.viajes, 0);
      expect(r.viajesRepetidos, 2);
      expect(RegistroDeViajes(viva).ultimos(10), hasLength(2));
    });

    test('el resumen cuenta lo que pasó, en palabras', () {
      sembrar(viva, viajes: 1, puntosPorViaje: 5);
      respaldoCon(viajes: 1, puntos: 6, desde: otraNoche);
      final otra = Base.abrir(rutaRespaldo);
      sembrar(otra, viajes: 1, puntosPorViaje: 5); // el repetido
      otra.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      otra.cerrar();

      final r = sumarRespaldo(
        viva: viva,
        ruta: rutaRespaldo,
        carpetaDeTrabajo: dir.path,
      );
      expect(r.viajes, 1);
      expect(r.viajesRepetidos, 1);
      expect(r.resumen, contains('1 viaje'));
      expect(r.resumen, contains('6 puntos'));
      expect(r.resumen, contains('Se salteó 1 que ya estaba'));
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

    test('toda tabla que se importa está en UNO de los dos grupos', () {
      /* `tablasQueSeImportan` se arma con los dos, así que esto comprueba que
         nadie le agregue una a mano y la deje sin decidir cómo se suma. */
      expect(tablasQueSeImportan, [
        'viajes',
        ...tablasAtadasAlViaje,
        ...tablasSueltas,
      ]);
      expect(
        tablasAtadasAlViaje.toSet().intersection(tablasSueltas.toSet()),
        isEmpty,
      );
    });

    test('las que viven sueltas tienen por dónde reconocerse', () {
      /* Sin llave natural no se pueden sumar sin duplicar: la suma tiraría, y
         mejor que falle acá que en el teléfono de Mauro. */
      for (final tabla in ['viajes', ...tablasSueltas]) {
        expect(
          llaveNatural[tabla],
          isNotEmpty,
          reason: '"$tabla" se suma de a una y no tiene con qué compararse',
        );
      }
    });

    test(
      'las que cuelgan de un viaje NO llevan llave: la del viaje alcanza',
      () {
        for (final tabla in tablasAtadasAlViaje) {
          expect(
            llaveNatural.containsKey(tabla),
            isFalse,
            reason:
                '"$tabla" entra o no entra con su viaje; una llave propia acá '
                'sólo puede contradecir esa decisión',
          );
        }
      },
    );

    test('los campos de cada llave existen de verdad en su tabla', () {
      /* Un campo mal escrito acá no da error de compilación: da un SQL que
         falla recién el día que alguien aprieta Sumar. */
      final b = Base.abrir('${dir.path}/para-las-llaves.db');
      for (final e in llaveNatural.entries) {
        final columnas = b.db
            .select('PRAGMA table_info(${e.key})')
            .map((f) => f['name'] as String)
            .toSet();
        expect(columnas, isNotEmpty, reason: 'no existe la tabla "${e.key}"');
        for (final campo in e.value) {
          expect(
            columnas,
            contains(campo),
            reason: '"${e.key}" no tiene la columna "$campo"',
          );
        }
      }
      b.cerrar();
    });
  });
}
