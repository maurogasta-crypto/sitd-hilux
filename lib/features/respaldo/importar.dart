/// Volver a meter un respaldo en el teléfono: sumándolo o reemplazando.
///
/// ## Por qué faltaba, y por qué entra ahora
///
/// Desde `sitd-7` se puede sacar una copia de la base y no devolverla: el
/// respaldo guardaba la historia pero no la traía de vuelta. Mientras cada
/// tanda obligaba a desinstalar —y desinstalar borra el SQLite— eso era lo
/// único que separaba «tengo el archivo» de «tengo los viajes».
///
/// Con la clave de firma propia (`sitd-21`) una actualización ya no borra
/// nada, así que esto dejó de ser una urgencia. Sigue haciendo falta para tres
/// cosas que no se van: **la última desinstalación**, la que pasa de la firma
/// de depuración a la propia; **el teléfono que se rompe**; y **mudar la
/// historia al Note 9** cuando aparezca.
///
/// ## Las dos formas, y por qué la primera no alcanzaba
///
/// `sitd-23` trajo una sola: **reemplazar**. Está pensada para el teléfono
/// vacío —el que se acaba de formatear, el que reemplaza al que se rompió—,
/// donde borrar lo que hay es correcto porque no hay nada.
///
/// **Y el 2026-09-21 se vio el otro caso, que es el común.** Mauro tenía en el
/// teléfono dos viajes de esa noche —uno de 69.82 km— y en un archivo los dos
/// de la noche anterior —uno de 103.2 km—. Ninguno de los dos juegos contenía
/// al otro, y la única herramienta que había le hacía elegir cuál perder. El
/// cartel decía la verdad y la decisión igual era mala: el respaldo estaba
/// resolviendo «restaurar» cuando lo que hacía falta era **juntar**.
///
/// Así que ahora son dos, y la que se ofrece primero es **sumar**, porque es
/// la que no pierde nada.
///
/// ## Cómo se reconoce un viaje que ya está
///
/// Por el instante en que empezó. Dos viajes del mismo teléfono no pueden
/// arrancar en el mismo milisegundo, así que `inicio` alcanza y no hace falta
/// inventar un identificador nuevo ni comparar el contenido entero.
///
/// **Y ante un repetido gana el del teléfono, no el del archivo.** Es lo
/// conservador: el archivo es viejo por definición, y lo que está vivo puede
/// haberse corregido después —una nota, el odómetro que Mauro editó a mano—.
/// La contra hay que saberla: si la copia viva de un viaje quedó incompleta y
/// la del respaldo está entera, sumar NO la arregla. Para ese caso está
/// reemplazar.
///
/// ## Las cuatro cosas que tiene que hacer bien, valgan para la que valgan
///
/// 1. **Mirar la versión del esquema ANTES de tocar nada.** Una base más nueva
///    que la aplicación no se importa: las tablas que todavía no existen acá
///    se perderían en silencio, que es la peor forma de fallar. Una más vieja
///    sí, migrando una COPIA — nunca el archivo original de Mauro.
/// 2. **Decir exactamente qué pasa**, con los números de los dos lados.
///    «¿Estás seguro?» no es una pregunta: no dice qué pasa si uno dice que sí.
/// 3. **No dejar la base a medias.** Todo va en UNA transacción: si algo falla
///    en el medio, se deshace entero y el teléfono queda como estaba. Es la
///    diferencia entre un error y una pérdida.
/// 4. **No traerse la credencial del archivo.** Un `.db` de antes de `sitd-21`
///    la lleva adentro, y podría ser una que ya se rotó. La que vale es la que
///    el teléfono tiene AHORA: se guarda antes, se importa lo demás, y se
///    vuelve a escribir.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../core/db/base.dart';
import '../../core/db/esquema.dart';
import '../nube/credencial.dart';
import '../nube/sesion.dart';
import 'saneado.dart';

/// Las tablas cuyas filas **cuelgan de un viaje** y viajan con él.
///
/// No se las reconoce de a una: si el viaje entra, entran enteras; si el viaje
/// ya estaba, no entra ninguna. Por eso no tienen llave natural — su identidad
/// es la del viaje al que pertenecen.
const List<String> tablasAtadasAlViaje = ['puntos', 'vibraciones', 'subidas'];

/// Las que viven por su cuenta: una carga de combustible y un evento del
/// sistema no pertenecen a ningún viaje. Se reconocen de a una, por su llave
/// natural.
const List<String> tablasSueltas = ['cargas', 'eventos'];

/// Qué tablas viajan, y por qué `ajustes` no.
///
/// `ajustes` es la configuración de ESTE teléfono —el modo de GPS que le
/// anduvo, la credencial de la nube, los litros del tanque—, no la historia.
/// Traerla de otro aparato pisaría lo que acá funciona con lo que allá
/// funcionaba. La historia se muda; las mañas del teléfono, no.
///
/// **Si mañana entra una tabla nueva, entra acá en la misma tanda.** Hay una
/// prueba que compara esta lista contra las tablas del esquema y falla si
/// alguien agrega una y se olvida — es la misma red que las colecciones y sus
/// reglas.
const List<String> tablasQueSeImportan = [
  // `viajes` va PRIMERO: las de `tablasAtadasAlViaje` lo referencian, y el
  // borrado en cascada las limpia de arriba abajo. Al insertar, el orden es el
  // mismo.
  'viajes',
  ...tablasAtadasAlViaje,
  ...tablasSueltas,
];

/// Lo que no se muda, con el motivo al lado para que nadie lo agregue por
/// prolijidad.
const List<String> tablasQueNoSeImportan = ['ajustes'];

/// Por qué campos se reconoce que una fila del respaldo YA ESTÁ en el
/// teléfono. Sólo lo usa la suma; reemplazar borra todo y no compara nada.
///
/// Son campos que describen **cuándo pasó la cosa**, no cómo quedó guardada:
/// el `id` no sirve porque las dos bases numeran desde uno y cada una por su
/// lado, así que el viaje 2 de un archivo no tiene nada que ver con el viaje 2
/// del teléfono. Fue justamente el problema a resolver.
const Map<String, List<String>> llaveNatural = {
  // El instante en que arrancó. Dos viajes del mismo teléfono no pueden
  // empezar en el mismo milisegundo.
  'viajes': ['inicio'],
  // El instante de la carga. Nadie carga dos veces en el mismo milisegundo.
  'cargas': ['t'],
  // Acá sí hacen falta los tres: la bitácora escribe varias líneas en el mismo
  // milisegundo al arrancar, y se distinguen por lo que dicen.
  'eventos': ['t', 'origen', 'texto'],
};

/// Cuánto hay de cada cosa. Es lo que se le muestra a Mauro de los dos lados
/// antes de preguntarle nada.
class Inventario {
  final int viajes;
  final int puntos;
  final int cargas;
  final int vibraciones;

  const Inventario({
    this.viajes = 0,
    this.puntos = 0,
    this.cargas = 0,
    this.vibraciones = 0,
  });

  bool get vacio => viajes == 0 && puntos == 0 && cargas == 0;

  /// En los términos de quien mira la pantalla, no en los de la base.
  String get resumen => vacio
      ? 'sin viajes'
      : '$viajes ${viajes == 1 ? 'viaje' : 'viajes'}, '
            '$puntos ${puntos == 1 ? 'punto' : 'puntos'}, '
            '$cargas ${cargas == 1 ? 'carga' : 'cargas'}';
}

Inventario _inventariar(Database db) {
  return Inventario(
    viajes: _cuantos(db, 'viajes'),
    puntos: _cuantos(db, 'puntos'),
    cargas: _cuantos(db, 'cargas'),
    vibraciones: _cuantos(db, 'vibraciones'),
  );
}

/// Cuántas filas tiene [tabla], que puede llevar el prefijo `viejo.`.
///
/// Una base vieja puede no tener todavía la tabla. Cero es la verdad.
int _cuantos(Database db, String tabla) {
  try {
    return db.select('SELECT COUNT(*) AS n FROM $tabla').first['n'] as int;
  } on SqliteException {
    return 0;
  }
}

/// Qué se sabe de un archivo antes de tocarlo.
class RevisionRespaldo {
  /// `null` si se puede importar; si no, por qué no, en una frase.
  final String? problema;

  /// Lo que trae el archivo, cuando se pudo leer.
  final Inventario? candidato;

  /// Lo que hay ahora en el teléfono.
  final Inventario actual;

  /// La versión del esquema del archivo.
  final int? version;

  /// Cuántos viajes del archivo NO están en el teléfono: los que entrarían si
  /// se suma. Es el número que decide si sumar sirve de algo.
  final int viajesNuevos;

  /// Y cuántos ya están. `viajesNuevos + viajesRepetidos` es el total del
  /// archivo.
  final int viajesRepetidos;

  const RevisionRespaldo({
    required this.actual,
    this.problema,
    this.candidato,
    this.version,
    this.viajesNuevos = 0,
    this.viajesRepetidos = 0,
  });

  bool get sePuede => problema == null;

  /// Si sumar traería algo. Con `false`, sumar es un botón que no hace nada y
  /// la pantalla tiene que decirlo antes y no después.
  bool get sumarTraeAlgo => viajesNuevos > 0;

  /// Cuántos viajes quedarían en el teléfono después de sumar.
  int get viajesDespuesDeSumar => actual.viajes + viajesNuevos;
}

/// Mira el archivo SIN tocarlo y sin tocar la base viva.
RevisionRespaldo revisarRespaldo({required Base viva, required String ruta}) {
  final actual = _inventariar(viva.db);
  if (!File(ruta).existsSync()) {
    return RevisionRespaldo(actual: actual, problema: 'Ese archivo no está.');
  }

  Database? db;
  try {
    db = sqlite3.open(ruta, mode: OpenMode.readOnly);
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version > versionEsquema) {
      return RevisionRespaldo(
        actual: actual,
        version: version,
        problema:
            'Ese respaldo es de una versión MÁS NUEVA de la aplicación '
            '(esquema $version contra $versionEsquema). No se importa: lo que '
            'la aplicación todavía no sabe guardar se perdería sin aviso. '
            'Actualizá primero.',
      );
    }
    final tablas = db
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'viajes'",
        )
        .isNotEmpty;
    if (!tablas) {
      return RevisionRespaldo(
        actual: actual,
        version: version,
        problema:
            'Ese archivo es una base de datos, pero no de esta '
            'aplicación: no tiene la tabla de viajes.',
      );
    }

    // Cuáles de sus viajes ya están acá. La comparación sale de
    // `llaveNatural` y no de un literal, para que sea LA MISMA que después
    // aplica la suma: si acá dijera una cosa y allá otra, el cartel prometería
    // un número de viajes y entraría otro.
    final llave = llaveNatural['viajes']!;
    final campos = llave.join(', ');
    final aca = <String>{
      for (final f in viva.db.select('SELECT $campos FROM viajes'))
        _comoLlave(llave, f),
    };
    var nuevos = 0;
    var repetidos = 0;
    for (final f in db.select('SELECT $campos FROM viajes')) {
      if (!aca.add(_comoLlave(llave, f))) {
        repetidos++;
      } else {
        nuevos++;
      }
    }

    return RevisionRespaldo(
      actual: actual,
      candidato: _inventariar(db),
      version: version,
      viajesNuevos: nuevos,
      viajesRepetidos: repetidos,
    );
  } on SqliteException catch (e) {
    return RevisionRespaldo(
      actual: actual,
      problema:
          'Ese archivo no se puede abrir como base de datos (${e.message}).',
    );
  } finally {
    db?.close();
  }
}

/// Las columnas que tienen las DOS bases, en el orden de la de acá.
///
/// Una que esté acá y no en el respaldo —porque el respaldo es más viejo— se
/// deja afuera y toma su valor por defecto, que es exactamente lo que hay que
/// hacer: el dato no existía cuando se guardó.
List<String> _columnasComunes(Database db, String tabla) {
  List<String> de(String esquema) => db
      .select('PRAGMA $esquema.table_info($tabla)')
      .map((f) => f['name'] as String)
      .toList();
  final viejas = de('viejo').toSet();
  return de('main').where(viejas.contains).toList();
}

/// Las mismas columnas, sin el `id`: cuando una fila entra al lado de otras
/// que ya están, su número lo pone la base y no el archivo.
List<String> _columnasSinId(Database db, String tabla) =>
    _columnasComunes(db, tabla).where((c) => c != 'id').toList();

/// El andamio que comparten las dos formas de importar: copiar, migrar la
/// copia, sacarle lo que abre algo, pegarla al costado, y hacer [hacer]
/// adentro de UNA transacción.
///
/// Devuelve `null` si salió bien, o el motivo si no. **Si falla, la base queda
/// exactamente como estaba.**
///
/// [carpetaDeTrabajo] es donde se hace la copia que se migra. Tiene que ser de
/// la aplicación: el archivo de Mauro no se toca nunca.
String? _conElRespaldoAlLado({
  required Base viva,
  required String ruta,
  required String carpetaDeTrabajo,
  required void Function(Database db) hacer,
}) {
  final revision = revisarRespaldo(viva: viva, ruta: ruta);
  if (!revision.sePuede) return revision.problema;

  final copia = File('$carpetaDeTrabajo/importando.db');
  try {
    if (copia.existsSync()) copia.deleteSync();
    File(ruta).copySync(copia.path);

    // La copia se migra hasta la versión de esta aplicación. El original no se
    // abre para escribir en ningún momento.
    final migrada = Base.abrir(copia.path);
    migrada.cerrar();

    // Y se le saca la credencial, que puede venir de antes de `sitd-21` y ser
    // una que ya se rotó. Reusa el saneado del respaldo: una sola definición
    // de qué es lo que no puede viajar.
    sanearCopia(copia.path);

    // Lo que el teléfono tiene AHORA y tiene que seguir teniendo después.
    final credencial = viva.leerAjuste(claveDeLaCredencial);
    final sesion = viva.leerAjuste(claveDeLaSesion);

    final db = viva.db;
    db.execute(
      "ATTACH DATABASE '${copia.path.replaceAll("'", "''")}' AS viejo",
    );
    try {
      db.execute('BEGIN IMMEDIATE');
      try {
        hacer(db);
        db.execute('COMMIT');
      } catch (_) {
        /* Cualquier cosa, no sólo una de SQLite: un error de esta misma
           unidad tiene que deshacer la transacción igual. Y si no se
           deshiciera, el `DETACH` de abajo fallaría por estar adentro de una
           transacción abierta y la base quedaría trabada. */
        db.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      db.execute('DETACH DATABASE viejo');
    }

    // La credencial vuelve DESPUÉS y fuera de la transacción: `ajustes` no se
    // tocó, así que esto sólo repone lo que el saneado podría haber alterado
    // si algún día la lista de tablas cambiara.
    if (credencial != null && credencial.isNotEmpty) {
      viva.escribirAjuste(claveDeLaCredencial, credencial);
    }
    if (sesion != null && sesion.isNotEmpty) {
      viva.escribirAjuste(claveDeLaSesion, sesion);
    }
    return null;
  } on SqliteException catch (e) {
    return 'No se pudo importar: ${e.message}. La base quedó como estaba.';
  } on FileSystemException catch (e) {
    return 'No se pudo leer el archivo: ${e.message}';
  } finally {
    if (copia.existsSync()) {
      try {
        copia.deleteSync();
      } on FileSystemException {
        // Que no se pueda borrar el temporal no invalida la importación.
      }
    }
  }
}

/// Reemplaza la historia del teléfono por la del respaldo.
///
/// Es la forma para el teléfono VACÍO. Para juntar dos historias está
/// [sumarRespaldo], y es la que hay que ofrecer primero.
///
/// Devuelve `null` si salió bien, o el motivo si no.
String? importarRespaldo({
  required Base viva,
  required String ruta,
  required String carpetaDeTrabajo,
}) {
  return _conElRespaldoAlLado(
    viva: viva,
    ruta: ruta,
    carpetaDeTrabajo: carpetaDeTrabajo,
    hacer: (db) {
      // Borrar `viajes` arrastra en cascada a puntos, vibraciones y subidas;
      // se borran igual de a una para no depender de que las claves foráneas
      // estén encendidas en esta conexión.
      for (final tabla in tablasQueSeImportan.reversed) {
        db.execute('DELETE FROM $tabla');
      }
      for (final tabla in tablasQueSeImportan) {
        /* ── LAS COLUMNAS SE NOMBRAN, NO SE USA `SELECT *` ────────────────
           `INSERT INTO t SELECT * FROM viejo.t` copia POR POSICIÓN, así que
           depende de que las dos bases tengan las columnas en el mismo
           orden. Hoy lo están —las dos se arman corriendo las migraciones
           desde cero— pero eso es una coincidencia del camino, no una
           garantía: el día que alguien cree una tabla con las columnas ya
           puestas en vez de agregarlas con ALTER, el orden cambia y esto
           metería la precisión en el campo de los cortes SIN ERROR. Se
           nombran, y se usan sólo las que están en las dos.

           Acá SÍ se copia el `id`, al revés que en la suma: la tabla quedó
           vacía dos líneas más arriba, así que no hay con qué chocar, y
           conservarlo mantiene las referencias del archivo tal cual. */
        final columnas = _columnasComunes(db, tabla);
        if (columnas.isEmpty) continue;
        final lista = columnas.join(', ');
        db.execute(
          'INSERT INTO $tabla ($lista) SELECT $lista FROM viejo.$tabla',
        );
      }
    },
  );
}

/// Lo que dejó una suma. Con [problema] lleno no entró nada y la base quedó
/// como estaba.
class Sumado {
  final String? problema;

  /// Viajes que entraron, y los que se saltearon porque ya estaban.
  final int viajes;
  final int viajesRepetidos;

  /// Los puntos de esos viajes que entraron.
  final int puntos;

  /// Cargas de combustible, igual.
  final int cargas;
  final int cargasRepetidas;

  /// Líneas de bitácora. No se cuentan las repetidas: son ruido y nadie las
  /// va a extrañar.
  final int eventos;

  const Sumado({
    this.problema,
    this.viajes = 0,
    this.viajesRepetidos = 0,
    this.puntos = 0,
    this.cargas = 0,
    this.cargasRepetidas = 0,
    this.eventos = 0,
  });

  bool get salioBien => problema == null;

  /// Si no entró nada. Pasa cuando el respaldo es el mismo que ya se metió, y
  /// hay que decirlo con todas las letras: un «listo» ahí es una mentira.
  bool get nadaNuevo => viajes == 0 && cargas == 0 && eventos == 0;

  /// En los términos de quien mira la pantalla.
  String get resumen {
    if (problema != null) return problema!;
    if (nadaNuevo) {
      return 'No había nada nuevo: todo lo de ese respaldo ya estaba en el '
          'teléfono. No se tocó nada.';
    }
    final partes = <String>[];
    if (viajes > 0) {
      partes.add(
        '$viajes ${viajes == 1 ? 'viaje' : 'viajes'} '
        '($puntos ${puntos == 1 ? 'punto' : 'puntos'})',
      );
    }
    if (cargas > 0) {
      partes.add('$cargas ${cargas == 1 ? 'carga' : 'cargas'}');
    }
    final repetidos = viajesRepetidos + cargasRepetidas;
    final cola = repetidos == 0
        ? ''
        : repetidos == 1
        ? ' Se salteó 1 que ya estaba.'
        : ' Se saltearon $repetidos que ya estaban.';
    return 'Se sumaron ${partes.join(' y ')}.$cola';
  }
}

/// Junta la historia del respaldo con la del teléfono, sin perder ninguna de
/// las dos.
///
/// Es la que hay que ofrecer primero: no borra nada, y correrla dos veces con
/// el mismo archivo deja el mismo resultado que correrla una.
Sumado sumarRespaldo({
  required Base viva,
  required String ruta,
  required String carpetaDeTrabajo,
}) {
  var viajes = 0;
  var viajesRepetidos = 0;
  var puntos = 0;
  var cargas = 0;
  var cargasRepetidas = 0;
  var eventos = 0;

  final problema = _conElRespaldoAlLado(
    viva: viva,
    ruta: ruta,
    carpetaDeTrabajo: carpetaDeTrabajo,
    hacer: (db) {
      // ── Los viajes, de a uno ────────────────────────────────────────────
      //
      // Tiene que ser de a uno y no en bloque: de cada uno que entra hay que
      // saber CON QUÉ NÚMERO quedó, para reapuntarle los puntos, las
      // vibraciones y su fila de la cola de subida. Ése es todo el trabajo de
      // esta unidad, y es lo que la suma tiene de más que el reemplazo.
      final columnas = _columnasSinId(db, 'viajes').join(', ');
      final llave = llaveNatural['viajes']!;
      final campos = llave.join(', ');
      final yaEstan = <String>{
        for (final f in db.select('SELECT $campos FROM viajes'))
          _comoLlave(llave, f),
      };

      for (final f in db.select(
        'SELECT id, $campos FROM viejo.viajes ORDER BY id',
      )) {
        final viejoId = f['id'] as int;
        if (!yaEstan.add(_comoLlave(llave, f))) {
          viajesRepetidos++;
          continue;
        }

        db.execute(
          'INSERT INTO viajes ($columnas) '
          'SELECT $columnas FROM viejo.viajes WHERE id = ?',
          [viejoId],
        );
        // El número que le tocó acá, que no tiene por qué ser el que traía.
        final nuevoId = db.lastInsertRowId;
        viajes++;
        puntos += _cuantosDelViaje(db, 'puntos', viejoId);

        for (final tabla in tablasAtadasAlViaje) {
          final cols = _columnasSinId(db, tabla);
          if (!cols.contains('viaje')) continue;
          /* La columna `viaje` no se copia: se reemplaza por el número nuevo,
             ahí mismo en la lista del SELECT. Es la traducción entera. */
          final destino = cols.join(', ');
          final origen = cols.map((c) => c == 'viaje' ? '?' : c).join(', ');
          db.execute(
            'INSERT INTO $tabla ($destino) '
            'SELECT $origen FROM viejo.$tabla WHERE viaje = ?',
            [nuevoId, viejoId],
          );
        }
      }

      // ── Y lo que no cuelga de ningún viaje ──────────────────────────────
      for (final tabla in tablasSueltas) {
        final entro = _sumarPorLlave(db, tabla);
        if (tabla == 'cargas') {
          cargas = entro.entraron;
          cargasRepetidas = entro.repetidas;
        } else {
          eventos += entro.entraron;
        }
      }
    },
  );

  if (problema != null) return Sumado(problema: problema);
  return Sumado(
    viajes: viajes,
    viajesRepetidos: viajesRepetidos,
    puntos: puntos,
    cargas: cargas,
    cargasRepetidas: cargasRepetidas,
    eventos: eventos,
  );
}

int _cuantosDelViaje(Database db, String tabla, int viaje) {
  try {
    return db.select('SELECT COUNT(*) AS n FROM viejo.$tabla WHERE viaje = ?', [
          viaje,
        ]).first['n']
        as int;
  } on SqliteException {
    return 0;
  }
}

/// Mete de a una las filas de [tabla] que no estén ya, comparándolas por su
/// llave natural.
///
/// De a una y no con un `INSERT ... SELECT ... WHERE NOT EXISTS`: esa forma
/// lee la tabla en la que está escribiendo, y si lo que ya insertó cuenta o no
/// para el `NOT EXISTS` es justamente lo que SQLite no promete. Acá las llaves
/// que ya existen se leen ANTES, a un conjunto, y desde ahí la decisión es de
/// este código y no depende de nada. Son decenas o cientos de filas adentro de
/// una transacción: no se nota.
({int entraron, int repetidas}) _sumarPorLlave(Database db, String tabla) {
  final cols = _columnasSinId(db, tabla);
  if (cols.isEmpty) return (entraron: 0, repetidas: 0);

  // Sólo por los campos de la llave que existan de los dos lados. Si un
  // respaldo viejo no tuviera alguno, se compara por los que sí están: de más
  // se saltea una fila, nunca se duplica.
  final llave = (llaveNatural[tabla] ?? const <String>[])
      .where(cols.contains)
      .toList();
  if (llave.isEmpty) {
    throw StateError(
      'La tabla "$tabla" no tiene por dónde reconocerse: sin llave natural no '
      'se puede sumar sin duplicar. Agregale una a `llaveNatural`.',
    );
  }

  final campos = llave.join(', ');
  final yaEstan = <String>{
    for (final f in db.select('SELECT $campos FROM $tabla'))
      _comoLlave(llave, f),
  };

  final destino = cols.join(', ');
  var entraron = 0;
  var repetidas = 0;
  for (final f in db.select('SELECT id, $campos FROM viejo.$tabla')) {
    final k = _comoLlave(llave, f);
    if (!yaEstan.add(k)) {
      repetidas++;
      continue;
    }
    db.execute(
      'INSERT INTO $tabla ($destino) '
      'SELECT $destino FROM viejo.$tabla WHERE id = ?',
      [f['id']],
    );
    entraron++;
  }
  return (entraron: entraron, repetidas: repetidas);
}

/// Los campos de la llave como un solo texto comparable.
///
/// El separador es un carácter que no aparece en un número ni en el texto de
/// un evento, para que dos filas distintas no se hagan pasar por la misma al
/// pegar sus campos.
String _comoLlave(List<String> campos, Row fila) =>
    campos.map((c) => fila[c]).join('\u0000');
