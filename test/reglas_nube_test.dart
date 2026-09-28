import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/nube/respaldo_nube.dart';

/// El banco de las reglas de Firestore.
///
/// No corren contra Firestore —eso necesitaría el emulador y una cadena de
/// Node— pero sí comprueban lo que se puede comprobar leyendo el archivo, que
/// resulta ser justo lo que más caro sale equivocar: que no se escape un UID
/// real a un repositorio público, y que las cuatro decisiones de fondo sigan
/// escritas.
void main() {
  late String reglas;
  late Map<String, String> bloques;

  setUpAll(() {
    reglas = File('firestore.rules').readAsStringSync();
    bloques = bloquesPorColeccion(reglas);
  });

  // La que importa más. Este repositorio es público.
  //
  // Comprueba contra la LISTA de marcadores y no contra un prefijo, y el
  // cambio es del 2026-09-20. Antes pedía `startsWith('UID-')`, que dejaba
  // pasar cualquier nombre nuevo con esa forma: el marcador de Mauro se
  // llamaba acá `UID-DE-MAURO` y en `reglas.txt` del panel `TU-UID-ACA`, o
  // sea dos nombres para la misma cosa, y el panel no reconocía el de acá —
  // al tocar «Copiar para publicar» se negaba y no había forma de seguir
  // desde el teléfono. Es el mismo error que `perm`/`permiso` entre CasaYourte
  // y Casa Verde: misma idea, nombre distinto, y se rompe sin dar error.
  //
  // Con la lista, renombrar un marcador falla ACÁ en vez de fallar en el panel
  // seis meses después.
  const marcadores = ['TU-UID-ACA', 'UID-DEL-AGENTE'];

  test('NO hay un solo UID real: todos son marcadores conocidos', () {
    final uids = RegExp(r"uid == '([^']+)'")
        .allMatches(reglas)
        .map((m) => m.group(1)!)
        .toList();

    expect(uids, isNotEmpty, reason: 'si no hay ninguno, algo se borró');
    for (final u in uids) {
      expect(
        marcadores,
        contains(u),
        reason:
            'ese UID no es uno de los marcadores del ecosistema '
            '($marcadores). Si parece real, este repositorio es público; si es '
            'un marcador nuevo, el panel no lo va a saber completar.',
      );
    }
  });

  // Los dos tienen que estar. Sin el de Mauro nadie administra la base; sin el
  // del agente, el chat no puede leer los reportes y la ronda lo marca con ✖.
  test('los dos marcadores están, y son los que el panel sabe completar', () {
    for (final m in marcadores) {
      expect(reglas, contains(m), reason: 'falta el marcador $m');
    }
  });

  test('el teléfono escribe en las colecciones suyas', () {
    for (final c in ['reportes', 'recorridos', 'respaldos', 'partes']) {
      expect(
        bloques[c],
        contains('allow create: if esElTelefono()'),
        reason: 'el teléfono no puede escribir en $c',
      );
      // Un documento subido es un hecho del pasado.
      expect(bloques[c], contains('allow update: if false'));
      expect(bloques[c], contains('allow delete: if soyYo()'));
    }
  });

  test('el teléfono NO lee los reportes', () {
    /* Si la credencial del teléfono se conoce —y hay que asumir que sí—,
       quien la tenga no puede llevarse la historia de los reportes.

       **Y esto se pregunta POR BLOQUE, no sobre el archivo entero**, que es
       el cambio del 2026-09-21. Antes decía
       `isNot(contains('allow read: if esElTelefono'))` sobre todo el texto, y
       el día que se agregó `recorridos` con
       `allow read: if soyYo() || esElAgente() || esElTelefono();` la prueba
       siguió en verde sin mirar nada: el permiso nuevo no empezaba con esas
       palabras. Una prueba que pasa por casualidad es peor que no tenerla. */
    expect(
      leenDe(bloques['reportes']!),
      isNot(contains('esElTelefono')),
      reason: 'el teléfono quedó pudiendo leer los reportes',
    );
  });

  test('la lista COMPLETA de lo que el teléfono puede leer', () {
    /* Es el costo de la decisión del 2026-09-21 escrito como comprobación: la
       credencial que vive en el teléfono alcanza para leer exactamente esto y
       nada más. Si mañana el permiso se le cuela a otra colección, falla acá.

       **`analisis` estaba desde antes y no es un descuido:** es lo que el
       agente concluye, y la aplicación lo muestra en pantalla. No es dato
       medido ni recorrido; si se filtrara, lo que se lleva es una opinión mía
       sobre unos umbrales.

       **`respaldos` y sus `partes` entraron con `sitd-34`**, por pedido de
       Mauro: levantar la base entera en otro teléfono. Es lo mismo que
       `recorridos` pero de todos los viajes a la vez, y el costo está escrito
       al lado del bloque.

       La que no está es la que importa: `reportes`. */
    final lee = [
      for (final e in bloques.entries)
        if (leenDe(e.value).contains('esElTelefono')) e.key,
    ]..sort();
    expect(lee, ['analisis', 'partes', 'recorridos', 'respaldos']);
  });

  test('el agente lee reportes, recorridos y respaldos, y no los pisa', () {
    for (final c in ['reportes', 'recorridos', 'respaldos', 'partes']) {
      expect(
        leenDe(bloques[c]!),
        contains('esElAgente'),
        reason: 'el chat no podría leer $c, y es para lo que existe',
      );
    }
    // Un reporte subido es lo que midió el teléfono: ni yo lo toco.
    expect(reglas, contains('allow update: if false'));
  });

  // Lo que el agente concluye va en una colección APARTE, no adentro del
  // reporte: si mañana me equivoco en un análisis, se reescribe ése y el dato
  // medido sigue intacto.
  test('el agente escribe sus conclusiones en analisis/, no en reportes/', () {
    expect(reglas, contains('match /analisis/{id}'));
    expect(
      reglas,
      contains('allow create, update: if esElAgente() || soyYo()'),
    );
  });

  // El teléfono entra como Mauro porque no se creó un usuario aparte. El día
  // que se cree, se cambia esta función y nada más.
  test('el teléfono entra como Mauro, y está dicho en un solo lugar', () {
    expect(
      reglas,
      contains('function esElTelefono() {\n      return soyYo();'),
    );
  });

  // Rige el deny por defecto: una colección nueva entra con su regla o queda
  // inaccesible. Es la regla del ecosistema y acá vale igual.
  test('hay cierre: lo que no está nombrado queda negado', () {
    expect(reglas, contains('match /{document=**}'));
    expect(reglas, contains('allow read, write: if false'));
  });

  test('se limita la forma y el tamaño de lo que entra', () {
    expect(
      reglas,
      contains(
        "hasOnly(\n                         ['json', 'sello', 'generado'])",
      ),
    );
    expect(reglas, contains('json.size() < 900000'));
  });

  group('respaldos: las reglas y el código dicen lo mismo', () {
    // Cada una de éstas es un 403 que aparecería recién en el teléfono, con
    // la subida a mitad de camino. Acá aparece antes de publicar.
    test('el manifiesto tiene exactamente los campos que manda el código', () {
      expect(camposDeHasOnly(bloques['respaldos']!), camposDelManifiesto);
    });

    test('una parte tiene exactamente los campos que manda el código', () {
      expect(camposDeHasOnly(bloques['partes']!), camposDeUnaParte);
    });

    test('el techo de una parte es el del código, y la parte entra', () {
      final techo = RegExp(r'datos\.size\(\) <= (\d+)')
          .firstMatch(bloques['partes']!);
      expect(techo, isNotNull);
      expect(int.parse(techo!.group(1)!), techoDeUnaParteEnLasReglas);
      expect(bytesPorParte, lessThan(techoDeUnaParteEnLasReglas));
      // Y el techo deja lugar al resto del documento adentro del MiB.
      expect(techoDeUnaParteEnLasReglas, lessThan(1024 * 1024 - 1024));
    });

    test('el máximo de partes es el del código', () {
      expect(
        bloques['respaldos'],
        contains('request.resource.data.partes <= $maximoDePartes'),
      );
      expect(
        bloques['respaldos'],
        contains('request.resource.data.partes >= 1'),
      );
    });

    test('las partes cuelgan del manifiesto, no andan sueltas', () {
      // Si `partes` quedara al nivel de arriba, la regla valdría para una
      // colección `partes/` de la raíz y la ruta real —la subcolección— caería
      // en el cierre por defecto: 403 en la primera parte.
      expect(bloques['respaldos'], contains('match /partes/{parte}'));
    });

    test('a un respaldo terminado no se le agregan partes', () {
      expect(
        bloques['partes'],
        contains('!exists(/databases/\$(database)/documents/respaldos/\$(id))'),
      );
    });

    test('el nombre de una parte es el que arma el código', () {
      final patron = RegExp(r"parte\.matches\('([^']+)'\)")
          .firstMatch(bloques['partes']!);
      expect(patron, isNotNull);
      final re = RegExp('^${patron!.group(1)}\$');
      for (final i in [0, 1, 9, 10, maximoDePartes - 1]) {
        expect(re.hasMatch(nombreDeParte(i)), isTrue, reason: nombreDeParte(i));
      }
    });
  });
}

/// Los campos del primer `hasOnly([...])` de un bloque, en orden.
List<String> camposDeHasOnly(String bloque) {
  final m = RegExp(r'hasOnly\(\s*\[([^\]]*)\]').firstMatch(bloque);
  if (m == null) return const [];
  return [
    for (final c in RegExp(r"'([^']+)'").allMatches(m.group(1)!)) c.group(1)!,
  ];
}

/// El texto de cada `match /coleccion/{…} { … }`, por nombre de colección.
///
/// Existe porque preguntarle algo al archivo entero es preguntar mal: un
/// permiso que se agrega en una colección no se puede distinguir de uno que
/// se agrega en otra, y ése fue exactamente el agujero que dejó pasar el
/// `allow read` del teléfono el 2026-09-21.
Map<String, String> bloquesPorColeccion(String reglas) {
  final salida = <String, String>{};
  /* El comodín va en el patrón a propósito. `match /reportes/{id} {` tiene
     DOS llaves, y la primera es la de `{id}`: buscar «la primera llave
     después del nombre» agarra ésa, el conteo se cierra en el `}` de al lado
     y cada bloque sale valiendo «{id}». Pasó, y las tres pruebas nuevas
     fallaron con la lista vacía hasta que se arregló. */
  final inicio = RegExp(r'match /(\w+)/\{[^}]*\}\s*\{');
  for (final m in inicio.allMatches(reglas)) {
    var nivel = 0;
    var i = m.end - 1;
    final desde = i;
    while (i < reglas.length) {
      if (reglas[i] == '{') nivel++;
      if (reglas[i] == '}') {
        nivel--;
        if (nivel == 0) break;
      }
      i++;
    }
    salida[m.group(1)!] = reglas.substring(desde, i + 1);
  }
  return salida;
}

/// Las líneas de `allow read` de un bloque, juntas. Es sobre lo que hay que
/// preguntar quién lee: el resto del bloque habla de escribir.
String leenDe(String bloque) =>
    bloque.split('\n').where((l) => l.contains('allow read')).join(' ');
