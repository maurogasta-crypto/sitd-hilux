/// Sacar del respaldo lo que abre algo.
///
/// ## El agujero que cierra, con fecha
///
/// El 2026-09-21 Mauro compartió un respaldo completo para que lo revisara un
/// chat. Adentro, en la tabla `ajustes`, estaba **la contraseña de Firebase en
/// texto plano**: el botón de respaldo hacía `File(ruta).copy(...)`, una copia
/// cruda del archivo entero, y desde `sitd-17` la credencial de la nube vive
/// justamente ahí. La contraseña hubo que rotarla.
///
/// El proyecto tenía el instinto correcto aplicado al archivo equivocado: hay
/// una prueba que revisa el **texto entero** del reporte JSON para que no se
/// escape una coordenada, y no había ninguna equivalente para el `.db`.
///
/// ## Por qué no alcanza con `DELETE`
///
/// **SQLite no borra: marca la página como libre y deja el contenido donde
/// estaba.** Un `DELETE FROM ajustes` deja la contraseña legible con `grep`
/// sobre el archivo. Por eso acá va un `VACUUM`, que reconstruye el archivo
/// entero desde los datos vivos. Y por eso la comprobación de [loQueSeEscapa]
/// mira los BYTES del archivo y no una consulta: una consulta habría dicho que
/// sí, que estaba todo limpio.
///
/// ## Por qué además del `VACUUM` hay que sacar el WAL
///
/// El modo WAL viaja en el encabezado del archivo, así que la copia también
/// está en WAL: el borrado y el vacuum se irían a un `sitd.db-wal` aparte que
/// no se comparte, y el `.db` compartido seguiría trayendo lo viejo. El
/// `PRAGMA journal_mode = DELETE` de abajo es lo que lo evita.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../core/db/base.dart';
import '../nube/credencial.dart';
import '../nube/sesion.dart';

/// Las claves de `ajustes` que no salen del teléfono, por nombre.
///
/// Salen de donde se escriben, no de una copia: si mañana alguien renombra la
/// clave de la credencial, esta lista lo sigue sola.
const List<String> clavesQueNoSalen = [claveDeLaCredencial, claveDeLaSesion];

/// Y todo lo que empiece así, por si mañana entra una credencial nueva y nadie
/// se acuerda de agregarla a la lista de arriba. Las dos de hoy ya lo cumplen;
/// es la red, no el mecanismo.
const String prefijoDeLaNube = 'nube_';

const String _condicion = 'clave LIKE ? OR clave IN (?, ?)';

List<Object?> get _argumentos => [
  '$prefijoDeLaNube%',
  claveDeLaCredencial,
  claveDeLaSesion,
];

/// Lo que hay que buscar en la copia para saber si quedó algo, leído de la
/// base VIVA antes de tocar nada.
///
/// Devuelve los valores guardados tal cual —el JSON entero de la credencial y
/// el token— más la contraseña sola, por si el JSON se reescribiera con otro
/// espaciado. Nada de esto se muestra ni se registra en ningún lado: se usa
/// para buscarlo y se descarta.
List<String> valoresQueNoSalen(Base base) {
  final valores = <String>[];
  for (final clave in clavesQueNoSalen) {
    final v = base.leerAjuste(clave);
    if (v != null && v.isNotEmpty) valores.add(v);
  }
  final c = GuardaDeCredencial(base).credencial;
  if (c != null && c.clave.isNotEmpty) valores.add(c.clave);
  return valores;
}

/// Borra de [ruta] —que tiene que ser una COPIA, nunca la base viva— todo lo
/// que abre algo, y reconstruye el archivo.
///
/// Devuelve las claves que efectivamente sacó, para poder decirlo en pantalla.
List<String> sanearCopia(String ruta) {
  final db = sqlite3.open(ruta);
  try {
    // Ver el comentario de arriba: sin esto el borrado se va a un `-wal`.
    db.execute('PRAGMA journal_mode = DELETE');

    final hayTabla = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ajustes'",
    );
    if (hayTabla.isEmpty) return const [];

    final filas = db.select(
      'SELECT clave FROM ajustes WHERE $_condicion',
      _argumentos,
    );
    final sacadas = [for (final f in filas) f['clave'] as String];
    if (sacadas.isEmpty) return const [];

    db.execute('DELETE FROM ajustes WHERE $_condicion', _argumentos);
    // Lo que de verdad saca el texto del archivo.
    db.execute('VACUUM');
    return sacadas;
  } finally {
    db.close();
  }
}

/// El primero de [secretos] que siga estando en los bytes de [ruta], o `null`
/// si el archivo está limpio.
///
/// Se busca sobre el archivo crudo y no con una consulta, a propósito: lo que
/// se quiere descartar es justamente que algo haya quedado en una página que
/// la base ya no lee.
String? loQueSeEscapa(String ruta, Iterable<String> secretos) {
  final bytes = File(ruta).readAsBytesSync();
  for (final s in secretos) {
    if (s.isEmpty) continue;
    if (_contiene(bytes, utf8.encode(s))) return s;
  }
  return null;
}

bool _contiene(Uint8List heno, List<int> aguja) {
  if (aguja.isEmpty || aguja.length > heno.length) return false;
  final tope = heno.length - aguja.length;
  for (var i = 0; i <= tope; i++) {
    var j = 0;
    while (j < aguja.length && heno[i + j] == aguja[j]) {
      j++;
    }
    if (j == aguja.length) return true;
  }
  return false;
}
