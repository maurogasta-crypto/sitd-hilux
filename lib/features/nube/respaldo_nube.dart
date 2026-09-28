/// El respaldo COMPLETO en la nube: la base entera, partida en pedazos que
/// entran en un documento de Firestore.
///
/// ## Para qué, con las palabras de Mauro
///
/// «Que el software pueda subir los datos completos de respaldo para restaurar
/// una sesión en otro dispositivo con toda la información posible»
/// (2026-09-28). `recorridos/` ya devolvía un viaje por vez, con sus puntos y
/// su ficha; lo que no devolvía era **todo lo demás**: las cargas de
/// combustible, las ventanas de vibración que tardan meses en juntarse, la
/// bitácora, las pruebas de soporte. Esto sube el archivo entero de la base,
/// ya saneado, y al bajarlo entra por el MISMO camino que un respaldo traído
/// de Descargas — el cartel de Sumar o Reemplazar de siempre.
///
/// ## Por qué partido, y por qué comprimido
///
/// **Un documento de Firestore no pasa de 1 MiB**, y una base con un mes de
/// viajes ya pasa varias veces eso. Por eso el archivo se comprime con gzip y
/// se corta en pedazos de [bytesPorParte]. Medido con los dos respaldos
/// reales del 20 y el 21 de septiembre: gzip los deja en el 47 % y el 42 %, y
/// comprimido son unos **50 KiB por cada mil puntos** del GPS. Cada pedazo es un documento de
/// `respaldos/{id}/partes/`, y el documento `respaldos/{id}` es el
/// **manifiesto**: cuántas partes, cuánto mide cada cosa, de qué versión es.
///
/// **El manifiesto se escribe AL FINAL, y ése es todo el truco.** Si la
/// subida se corta a mitad de camino quedan partes sueltas pero no un
/// manifiesto, así que la lista del teléfono no muestra un respaldo roto: sólo
/// muestra los que terminaron de subir. Las partes huérfanas no hacen daño y
/// las borra Mauro desde la consola; las reglas no dejan agregarle partes a un
/// respaldo que ya tiene manifiesto, así que uno terminado no se puede
/// ensuciar después.
///
/// ## Y por qué gzip y no otra cosa
///
/// Viene con `dart:io`, así que no suma un paquete; y trae adentro su propio
/// control —un CRC-32 y el largo original—, así que una parte cambiada o
/// cortada **no se descomprime en silencio a una base rota**: tira un error, y
/// acá ese error se traduce a una frase. Encima de eso se comprueban los dos
/// largos del manifiesto y el encabezado de SQLite, porque «descomprimió» no
/// quiere decir «es una base».
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Cuánto lleva cada parte, en bytes ya comprimidos.
///
/// **700 KiB y no 1 MiB**, con margen a propósito: el límite de Firestore
/// cuenta también el nombre del documento y de los campos, y una parte que
/// quede justo en el borde rebota con un 400 que no dice por qué. La regla
/// de `firestore.rules` pone el techo en 750 000, así que este número tiene
/// que quedar abajo de ése — el banco lo compara.
const int bytesPorParte = 700 * 1024;

/// El techo de la regla, repetido acá sólo para que el banco pueda
/// comprobar que [bytesPorParte] entra. La que manda es la de las reglas.
const int techoDeUnaParteEnLasReglas = 750000;

/// Cuántas partes como mucho: 56 MB comprimidos.
///
/// **La cuenta, con los 50 KiB por mil puntos medidos arriba**: 80 partes son
/// alrededor de un millón cien mil puntos, unas **300 horas de manejo** a un
/// punto por segundo. Empezó en 40 y se dobló antes de publicar, con la
/// cuenta hecha: 40 eran 150 horas, que esta camioneta junta en pocos meses.
/// Cuando se acerque, [empacar] lo dice antes de subir nada, y el paso
/// siguiente no es subir el techo sino dejar de subir la historia entera
/// cada vez.
///
/// La regla lo repite: un manifiesto que prometa mil partes no se escribe.
const int maximoDePartes = 80;

/// Los campos del manifiesto. **La regla de Firestore los repite en su
/// `hasOnly`**, y el banco compara las dos listas: si alguien agrega un campo
/// acá sin tocar las reglas, la subida rebotaría con un 403 recién en el
/// teléfono.
const List<String> camposDelManifiesto = [
  'creado',
  'sello',
  'esquema',
  'bytesOriginal',
  'bytesComprimido',
  'partes',
  'resumen',
];

/// Los campos de cada parte, con la misma advertencia.
const List<String> camposDeUnaParte = ['i', 'datos'];

/// El nombre del documento de la parte [i]: `p000`, `p001`… Con ceros
/// adelante para que en la consola se vean en orden.
String nombreDeParte(int i) => 'p${i.toString().padLeft(3, '0')}';

/// El identificador del respaldo. Lleva el usuario adelante, igual que los
/// reportes, y el instante en que se armó: dos respaldos del mismo teléfono
/// no se pisan nunca.
String idDeRespaldo(String quien, int creado) => '$quien-r$creado';

/// Una base comprimida y cortada, lista para subir.
class Empaque {
  final List<Uint8List> partes;
  final int bytesOriginal;
  final int bytesComprimido;

  const Empaque({
    required this.partes,
    required this.bytesOriginal,
    required this.bytesComprimido,
  });
}

/// El encabezado con el que empieza todo archivo de SQLite.
final Uint8List _encabezadoSqlite = Uint8List.fromList(
  utf8.encode('SQLite format 3\u0000'),
);

bool _esSqlite(Uint8List b) {
  if (b.length < _encabezadoSqlite.length) return false;
  for (var i = 0; i < _encabezadoSqlite.length; i++) {
    if (b[i] != _encabezadoSqlite[i]) return false;
  }
  return true;
}

/// Comprime [base] y la corta en partes de a lo sumo [porParte] bytes.
///
/// Lanza [FormatException] si lo que se le pasa no es una base de SQLite, o
/// si comprimido no entra en [maximoDePartes]: es mejor enterarse acá que
/// después de haber subido la mitad.
Empaque empacar(Uint8List base, {int porParte = bytesPorParte}) {
  if (!_esSqlite(base)) {
    throw const FormatException('Eso no es una base de SQLite.');
  }
  final comprimido = Uint8List.fromList(gzip.encode(base));
  final partes = <Uint8List>[];
  for (var i = 0; i < comprimido.length; i += porParte) {
    final fin = i + porParte < comprimido.length
        ? i + porParte
        : comprimido.length;
    partes.add(Uint8List.sublistView(comprimido, i, fin));
  }
  if (partes.length > maximoDePartes) {
    throw FormatException(
      'El respaldo comprimido ocupa ${partes.length} partes y el techo es '
      '$maximoDePartes. Hay que subir el techo en el código y en las reglas.',
    );
  }
  return Empaque(
    partes: partes,
    bytesOriginal: base.length,
    bytesComprimido: comprimido.length,
  );
}

/// Junta las [partes], las descomprime y devuelve la base.
///
/// Una parte `null` es una parte que no llegó. **Cada forma de romperse tiene
/// su frase**, en `FormatException`: que falte una parte, que el largo no
/// cierre, que el gzip no valide o que lo que salió no sea una base. Las
/// cuatro se ven igual desde afuera —«no se pudo»— y se arreglan distinto.
Uint8List desempacar(
  List<Uint8List?> partes, {
  required int bytesOriginal,
  required int bytesComprimido,
}) {
  if (partes.isEmpty) {
    throw const FormatException('El respaldo no tiene ninguna parte.');
  }
  final faltan = [
    for (var i = 0; i < partes.length; i++)
      if (partes[i] == null) i,
  ];
  if (faltan.isNotEmpty) {
    throw FormatException(
      'Faltan ${faltan.length} de ${partes.length} partes del respaldo '
      '(la primera es la ${faltan.first}).',
    );
  }
  final junto = BytesBuilder(copy: false);
  for (final p in partes) {
    junto.add(p!);
  }
  final comprimido = junto.takeBytes();
  if (comprimido.length != bytesComprimido) {
    throw FormatException(
      'Las partes suman ${comprimido.length} bytes y el manifiesto dice '
      '$bytesComprimido: alguna llegó cortada.',
    );
  }
  final List<int> abierto;
  try {
    abierto = gzip.decode(comprimido);
  } on FormatException {
    throw const FormatException(
      'El respaldo no se puede descomprimir: alguna parte llegó cambiada.',
    );
  }
  final base = abierto is Uint8List ? abierto : Uint8List.fromList(abierto);
  if (base.length != bytesOriginal) {
    throw FormatException(
      'Descomprimido mide ${base.length} bytes y el manifiesto dice '
      '$bytesOriginal.',
    );
  }
  if (!_esSqlite(base)) {
    throw const FormatException('Lo que se bajó no es una base de SQLite.');
  }
  return base;
}

/// Lo que se sabe de un respaldo que está en la nube, sin bajar las partes.
class RespaldoEnLaNube {
  final String id;

  /// Cuándo se armó, en milisegundos.
  final int creado;
  final String sello;
  final int esquema;
  final int bytesOriginal;
  final int bytesComprimido;
  final int partes;

  /// Qué trae, en las palabras de `Inventario.resumen`: «12 viajes, 40312
  /// puntos, 3 cargas». Es lo que deja elegir uno de una lista sin bajarlo.
  final String resumen;

  const RespaldoEnLaNube({
    required this.id,
    required this.creado,
    required this.sello,
    required this.esquema,
    required this.bytesOriginal,
    required this.bytesComprimido,
    required this.partes,
    required this.resumen,
  });

  /// Los campos del manifiesto, en el formato de Firestore REST.
  ///
  /// Las claves salen de [camposDelManifiesto] por nombre, así que un campo
  /// que falte acá o sobre allá lo agarra el banco.
  Map<String, dynamic> get campos => {
    'creado': {'integerValue': '$creado'},
    'sello': {'stringValue': sello},
    'esquema': {'integerValue': '$esquema'},
    'bytesOriginal': {'integerValue': '$bytesOriginal'},
    'bytesComprimido': {'integerValue': '$bytesComprimido'},
    'partes': {'integerValue': '$partes'},
    'resumen': {'stringValue': resumen},
  };

  /// Lee un manifiesto como lo devuelve Firestore. `null` si le falta algo
  /// imprescindible: un manifiesto a medias no se puede bajar, y es mejor no
  /// mostrarlo que ofrecer algo que va a fallar.
  static RespaldoEnLaNube? desdeFirestore(String id, Object? campos) {
    if (campos is! Map) return null;
    int? entero(String c) {
      final v = campos[c];
      final s = v is Map ? v['integerValue'] : null;
      return s is String ? int.tryParse(s) : (s is int ? s : null);
    }

    String texto(String c) {
      final v = campos[c];
      final s = v is Map ? v['stringValue'] : null;
      return s is String ? s : '';
    }

    final creado = entero('creado');
    final original = entero('bytesOriginal');
    final comprimido = entero('bytesComprimido');
    final partes = entero('partes');
    if (creado == null ||
        original == null ||
        comprimido == null ||
        partes == null ||
        partes < 1) {
      return null;
    }
    return RespaldoEnLaNube(
      id: id,
      creado: creado,
      sello: texto('sello'),
      esquema: entero('esquema') ?? 0,
      bytesOriginal: original,
      bytesComprimido: comprimido,
      partes: partes,
      resumen: texto('resumen'),
    );
  }
}

/// Los campos de la parte [i], en el formato de Firestore REST.
///
/// **Van como `bytesValue` y no como texto**: Firestore guarda los bytes tal
/// cual y el límite de 1 MiB los cuenta crudos. En base64 adentro de un
/// `stringValue` ocuparían un tercio más del documento.
Map<String, dynamic> camposDeParte(int i, Uint8List datos) => {
  'i': {'integerValue': '$i'},
  'datos': {'bytesValue': base64Encode(datos)},
};

/// Saca los bytes de una parte como la devuelve Firestore, o `null`.
Uint8List? datosDeParte(Object? campos) {
  if (campos is! Map) return null;
  final v = campos['datos'];
  final s = v is Map ? v['bytesValue'] : null;
  if (s is! String) return null;
  try {
    return base64Decode(s);
  } on FormatException {
    return null;
  }
}
