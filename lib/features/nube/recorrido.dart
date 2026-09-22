/// El recorrido de un viaje, empaquetado para que quepa en un documento.
///
/// ## Qué cambia acá, dicho con todas las letras
///
/// Hasta el 2026-09-21 este proyecto tenía una regla escrita en cinco lugares:
/// **el recorrido no sale del teléfono por ningún canal**, y ése era el motivo
/// por el que se pudo aceptar que existiera una nube. Mauro la dio vuelta ese
/// día, a propósito y con la frase «por más que haya puntos o coordenadas»:
/// en esta etapa quiere poder cruzar TODOS los datos desde el chat, y sin el
/// recorrido la mitad de las preguntas no se pueden contestar.
///
/// **Lo que de verdad cambia es UNA cosa, y no es la que parece.** No es el
/// teléfono: un teléfono robado y desbloqueado ya tiene el recorrido entero en
/// su SQLite, así que dejarlo leer lo que él mismo subió no le agrega nada.
/// Lo nuevo es que **el recorrido pasa a existir en un segundo lugar**, y ahí
/// lo protege la cuenta de Firebase de Mauro y nada más. Eso es irreversible:
/// lo que se escribe queda escrito aunque después se borre.
///
/// Por eso va a una colección propia (`recorridos/`) con su propia regla, que
/// es el mismo razonamiento con el que `analisis/` está separado de
/// `reportes/`: si algo sale mal, sale mal en un solo lugar.
///
/// ## Por qué no se manda el JSON tal cual
///
/// Un documento de Firestore no pasa de 1 MiB. El viaje del 2026-09-21 tiene
/// **5343 puntos**, y con una lista por punto son 584 KiB — entra, pero
/// apretado, y un viaje de tres horas no entraría. Medido sobre ese viaje:
///
/// | Forma | Tamaño | Por punto |
/// |---|---|---|
/// | una lista por punto, JSON crudo | 584 KiB | 112 B |
/// | columnas paralelas, en deltas | 117 KiB | 22 B |
///
/// Son cinco veces menos por dos ideas que se suman. **Columnas paralelas:**
/// todos los `lat` juntos, todos los `lon` juntos. **Deltas:** de cada valor
/// se guarda cuánto cambió respecto del anterior, y entre dos muestras
/// separadas un segundo eso son números de dos o tres cifras en vez de los
/// quince de una coordenada.
///
/// ## Y por qué redondear no pierde nada
///
/// Cada columna se cuantiza a lo que el sensor de verdad sabe, ni más ni
/// menos. La posición va a 1e-6 grados: eso mete un error de **hasta 6 cm**,
/// contra una precisión medida en ese mismo viaje de **3,8 a 10,4 m**. O sea
/// que el redondeo es unas cien veces más chico que el error que ya traía el
/// dato. Guardar los quince decimales que escupe Android sería guardar ruido
/// con formato de precisión.
///
/// **Cuánto se elige NO es una cuestión de gusto, y está medido**: ver la
/// tabla al lado de `'lat'` en [escalasDelRecorrido]. El primer borrador usó
/// 1e-5 y le corría el haversine de control 73 m por viaje.
///
/// **El instante NO se redondea.** Va en milisegundos y exacto, porque la
/// distancia se integra multiplicando velocidad por `dt`: perder medio segundo
/// por muestra sería perder metros, que es justamente lo que este proyecto
/// mide. Los deltas de tiempo ya son chicos por sí solos.
library;

import 'dart:convert';

import '../odometro/muestra.dart';

/// Versión del formato. Igual que `versionEsquema`: un recorrido de una
/// versión que esta compilación no conoce **no se abre**, en vez de abrirse
/// mal y en silencio.
const int versionDelRecorrido = 1;

/// Por cuánto se multiplica cada columna antes de redondearla al entero.
///
/// Es la tabla que define cuánta precisión sobrevive, y está acá —en un solo
/// lugar, y viajando ADENTRO del documento— para que un recorrido guardado
/// hoy se pueda leer el día que estos números cambien.
const Map<String, int> escalasDelRecorrido = {
  // Milisegundos, exacto. Ver el porqué arriba.
  't': 1,
  /* 1e-6 grados ≈ 11 cm, y NO 1e-5 como decía el primer borrador. El cambio
     se midió sobre el viaje real de 5343 puntos antes de dejar el formato
     fijo, y la tabla es el argumento entero:

       escala    doc      haversine reconstruido
       1e-5    108,8 KiB  +73,3 m sobre 69,70 km
       1e-6    117,2 KiB   +1,2 m      ← ocho kilobytes más, sesenta veces mejor
       1e-7    126,7 KiB   +0,0 m

     La distancia que este proyecto usa —la Doppler— no se movía en ninguno
     de los tres casos: sale de velocidad × tiempo, y el tiempo va exacto. El
     que se degradaba era el HAVERSINE, que es el control cruzado, y siempre
     hacia arriba: es el mismo «el ruido de posición siempre suma y nunca
     resta» que el proyecto ya tiene escrito para la odometría, apareciendo
     acá por la puerta de atrás. Un control que se corre 73 m en cada viaje
     deja de servir para controlar, y ocho kilobytes es un precio que no se
     discute. */
  'lat': 1000000,
  'lon': 1000000,
  // 10 cm. El error vertical del GPS es varias veces el horizontal.
  'alt': 10,
  // 1 cm/s. El Doppler tiene ~10 cm/s de error.
  'vel': 100,
  'pm': 10,
  'pv': 100,
};

/// Las columnas que pueden venir vacías, según el esquema.
///
/// `alt` y `precision_vel` son `REAL` sin `NOT NULL`: no todos los receptores
/// las informan. En los viajes del Redmi 15 vienen las dos siempre, pero el
/// formato no puede depender de eso — un Note 9 podría no darlas.
const List<String> columnasQuePuedenFaltar = ['alt', 'pv'];

/// Empaqueta los puntos de un viaje en el texto que va a la nube.
///
/// Devuelve JSON, no binario, a propósito: es lo que deja mirar un recorrido
/// con `curl` y un `jq` el día que algo no cierre, sin tener que correr esta
/// aplicación para saber qué dice.
String codificarRecorrido(List<Muestra> puntos) {
  List<int> columna(
    num? Function(Muestra) sacar,
    int escala,
    List<int>? sinDato,
  ) {
    final salida = <int>[];
    var previo = 0;
    for (var i = 0; i < puntos.length; i++) {
      final v = sacar(puntos[i]);
      if (v == null) {
        /* El hueco se anota aparte y la cadena de deltas NO se mueve: si el
           valor que falta corriera el acumulado, todos los siguientes saldrían
           desplazados. Se guarda un cero, que con `previo` quieto significa
           «lo mismo que el anterior», y al abrir se vuelve a poner en nulo. */
        sinDato!.add(i);
        salida.add(0);
        continue;
      }
      final q = (v * escala).round();
      salida.add(q - previo);
      previo = q;
    }
    return salida;
  }

  final sinAlt = <int>[];
  final sinPv = <int>[];
  final e = escalasDelRecorrido;

  final mapa = <String, dynamic>{
    'v': versionDelRecorrido,
    'n': puntos.length,
    'esc': e,
    't': columna((m) => m.t, e['t']!, null),
    'lat': columna((m) => m.lat, e['lat']!, null),
    'lon': columna((m) => m.lon, e['lon']!, null),
    'alt': columna((m) => m.alt, e['alt']!, sinAlt),
    'vel': columna((m) => m.velocidad, e['vel']!, null),
    'pm': columna((m) => m.precision, e['pm']!, null),
    'pv': columna((m) => m.precisionVel, e['pv']!, sinPv),
  };
  // Sólo si hay huecos: el caso normal no paga por el caso raro.
  if (sinAlt.isNotEmpty) mapa['sin_alt'] = sinAlt;
  if (sinPv.isNotEmpty) mapa['sin_pv'] = sinPv;

  return jsonEncode(mapa);
}

/// Vuelve a armar los puntos desde el texto de la nube.
///
/// Lanza [FormatException] con una frase entendible si el texto no es un
/// recorrido de esta aplicación o es de una versión que no conoce. **No
/// devuelve una lista a medias:** un recorrido incompleto que parece completo
/// haría salir kilómetros de menos sin que nada avise, que es la forma de
/// fallar que este proyecto ya pagó dos veces.
List<Muestra> decodificarRecorrido(String texto) {
  Object? crudo;
  try {
    crudo = jsonDecode(texto);
  } on FormatException {
    throw const FormatException('Ese texto no es un recorrido: no es JSON.');
  }
  if (crudo is! Map) {
    throw const FormatException('Ese recorrido no tiene la forma esperada.');
  }
  final doc = crudo;

  final version = doc['v'];
  if (version is! int) {
    throw const FormatException('Ese recorrido no dice de qué versión es.');
  }
  if (version > versionDelRecorrido) {
    throw FormatException(
      'Ese recorrido es de una versión más nueva de la aplicación '
      '(formato $version contra $versionDelRecorrido). Actualizá primero: '
      'abrirlo con esta compilación leería mal lo que no conoce.',
    );
  }

  final n = doc['n'];
  if (n is! int || n < 0) {
    throw const FormatException('Ese recorrido no dice cuántos puntos trae.');
  }

  // Las escalas salen del DOCUMENTO y no de la constante de arriba: si mañana
  // se cuantiza distinto, lo guardado hoy se sigue leyendo bien.
  final esc = doc['esc'];
  if (esc is! Map) {
    throw const FormatException('Ese recorrido no trae sus escalas.');
  }
  int escala(String c) {
    final v = esc[c];
    if (v is! int || v <= 0) {
      throw FormatException('La escala de "$c" no sirve: $v.');
    }
    return v;
  }

  List<double> columna(String c) {
    final lista = doc[c];
    if (lista is! List || lista.length != n) {
      throw FormatException(
        'A la columna "$c" del recorrido le faltan valores: '
        '${lista is List ? lista.length : 'ninguno'} en vez de $n.',
      );
    }
    final e = escala(c);
    final salida = <double>[];
    var acumulado = 0;
    for (final d in lista) {
      if (d is! int) {
        throw FormatException('La columna "$c" tiene algo que no es número.');
      }
      acumulado += d;
      salida.add(acumulado / e);
    }
    return salida;
  }

  Set<int> huecos(String clave) {
    final v = doc[clave];
    if (v == null) return const {};
    if (v is! List) throw FormatException('"$clave" no es una lista.');
    return {
      for (final i in v)
        if (i is int) i,
    };
  }

  final t = columna('t');
  final lat = columna('lat');
  final lon = columna('lon');
  final alt = columna('alt');
  final vel = columna('vel');
  final pm = columna('pm');
  final pv = columna('pv');
  final sinAlt = huecos('sin_alt');
  final sinPv = huecos('sin_pv');

  return [
    for (var i = 0; i < n; i++)
      Muestra(
        t: t[i].round(),
        lat: lat[i],
        lon: lon[i],
        alt: sinAlt.contains(i) ? null : alt[i],
        velocidad: vel[i],
        precision: pm[i],
        precisionVel: sinPv.contains(i) ? null : pv[i],
      ),
  ];
}
