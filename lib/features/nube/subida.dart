import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/bitacora.dart';
import 'credencial.dart';
import 'sesion.dart';

/// Cómo salió un intento de subir.
class Resultado {
  final bool ok;

  /// Por qué no salió, en palabras que sirvan. `null` si salió.
  final String? falla;

  /// `true` cuando no tiene sentido reintentar solo —falta configurar, o la
  /// contraseña es incorrecta—. Se distingue de «no había señal», que sí se
  /// reintenta.
  final bool esCulpaNuestra;

  const Resultado.bien() : ok = true, falla = null, esCulpaNuestra = false;

  const Resultado.mal(this.falla, {this.esCulpaNuestra = false}) : ok = false;
}

/// Habla con Firestore: sube reportes, sube recorridos y **baja** recorridos.
///
/// Se llama `Subida` por historia —nació sólo subiendo— y se quedó con el
/// nombre a propósito: renombrarla tocaría cinco archivos para no cambiar
/// nada. Lo que la define es que es el ÚNICO lugar que sabe autenticarse
/// contra esta base, y por eso lo nuevo entra acá en vez de armar una segunda
/// copia de `_entrar`.
///
/// ## Por qué REST y no el SDK de Firebase
///
/// El SDK de Android necesita un `google-services.json` **adentro del
/// repositorio**, y este repositorio es público. La API REST no necesita
/// ningún archivo: alcanza con el identificador del proyecto y la clave de
/// API, que son los dos datos que Mauro pega en el teléfono. Además evita
/// sumar un paquete pesado a una aplicación cuyo trabajo real es medir sin
/// conexión.
///
/// ## Por qué el reporte va como UN campo de texto
///
/// Firestore REST pide cada valor con su tipo (`stringValue`, `doubleValue`,
/// `mapValue`, `arrayValue`…), así que guardar el reporte con su forma
/// original obligaría a escribir un traductor recursivo — código nuevo, con
/// sus propios errores, para un dato que de todos modos se lee entero. El
/// reporte va serializado en un solo campo de texto y se vuelve a abrir con un
/// `JSON.parse` del otro lado.
///
/// La contra, dicha: no se puede consultar adentro del reporte desde
/// Firestore. No hace falta — quien lo lee soy yo, y lo leo completo.
class Subida {
  final http.Client cliente;

  /// Cuánto se espera a la red antes de darla por perdida. Corto a propósito:
  /// esto corre cuando alguien acaba de terminar un viaje, y una aplicación
  /// que se queda pensando parece colgada.
  final Duration espera;

  Subida({http.Client? cliente, this.espera = const Duration(seconds: 20)})
    : cliente = cliente ?? http.Client();

  /// Consigue un `idToken` para escribir, o `null`.
  ///
  /// **Prueba primero con el `refreshToken` guardado**, y sólo cae en la
  /// contraseña si no hay token o si el que hay dejó de servir. Es lo que
  /// permite que la contraseña no tenga que vivir en el teléfono: se usa una
  /// vez, se guarda el token que devuelve el login, y de ahí en más se
  /// renueva con eso.
  ///
  /// El token muerto —revocado desde la consola, o caducado— se olvida en vez
  /// de reintentarse para siempre: si no, un token revocado dejaría la
  /// aplicación sin poder subir y sin decir por qué.
  Future<String?> _entrar(Credencial c, GuardaDeSesion? sesion) async {
    final guardado = sesion?.token;
    if (guardado != null) {
      final t = await _renovar(c, guardado);
      if (t != null) return t;
      sesion?.olvidar();
    }
    return _conContrasena(c, sesion);
  }

  /// Cambia el `refreshToken` por un `idToken` nuevo.
  Future<String?> _renovar(Credencial c, String refresco) async {
    final r = await cliente
        .post(
          Uri.parse(
            'https://securetoken.googleapis.com/v1/token?key=${c.apiKey}',
          ),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'grant_type': 'refresh_token', 'refresh_token': refresco},
        )
        .timeout(espera);
    if (r.statusCode != 200) return null;
    final m = jsonDecode(r.body);
    // Ojo con el nombre: este extremo contesta en snake_case, no en camelCase
    // como el de `signInWithPassword`. Es el mismo Firebase y son dos APIs.
    return m is Map ? m['id_token'] as String? : null;
  }

  /// El login de siempre. Guarda el `refreshToken` que devuelve, que es lo
  /// que hace que esto no tenga que repetirse.
  Future<String?> _conContrasena(Credencial c, GuardaDeSesion? sesion) async {
    if (c.clave.isEmpty) return null;
    final r = await cliente
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:'
            'signInWithPassword?key=${c.apiKey}',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': c.mail,
            'password': c.clave,
            'returnSecureToken': true,
          }),
        )
        .timeout(espera);
    if (r.statusCode != 200) return null;
    final m = jsonDecode(r.body);
    if (m is! Map) return null;
    final refresco = m['refreshToken'] as String?;
    if (refresco != null && refresco.isNotEmpty) sesion?.guardar(refresco);
    return m['idToken'] as String?;
  }

  /// Sube un reporte con el identificador [id].
  ///
  /// **No lanza nunca.** Que no haya señal es el caso normal en una camioneta,
  /// no un error: se devuelve el motivo y la cola reintenta.
  ///
  /// El POST, el login y los códigos de error los pone [_escribir], que es el
  /// mismo camino que usa el recorrido: dos copias del manejo de errores son
  /// dos cosas que se pueden arreglar sólo en una.
  Future<Resultado> subir({
    required Credencial credencial,
    required String id,
    required Map<String, dynamic> reporte,
    GuardaDeSesion? sesion,
  }) {
    return _escribir(
      credencial: credencial,
      coleccion: 'reportes',
      id: id,
      sesion: sesion,
      que: 'El reporte $id',
      campos: {
        // El reporte entero, serializado. Ver el porqué arriba.
        'json': {'stringValue': jsonEncode(reporte)},
        // Dos campos sueltos para poder ordenar y mirar sin abrir el texto.
        // Nada más: lo que vale está adentro del `json`.
        'sello': {'stringValue': '${(reporte['app'] as Map?)?['sello'] ?? ''}'},
        'generado': {'integerValue': '${reporte['generado'] ?? 0}'},
      },
    );
  }

  /// Sube el recorrido de un viaje a `recorridos/`.
  ///
  /// **Va a una colección aparte y no adentro del reporte**, y ésa es la
  /// decisión entera de esta tanda. `reportes/` tiene una propiedad que se
  /// comprueba con una prueba que busca `"lat"` en su texto entero: no lleva
  /// una sola coordenada. Meter el recorrido ahí la rompería y dejaría lo
  /// sensible mezclado con lo que no lo es. Separado, la regla de `recorridos/`
  /// es propia, se puede negar sola, y si algo sale mal sale mal en un lugar.
  /// **Y va con la FICHA del viaje al lado**, no sólo con los puntos. Sin ella
  /// la nube tendría el recorrido y no el viaje al que pertenece: al bajarlo
  /// habría que inventar los kilómetros, los cortes y el odómetro, o dejarlos
  /// vacíos. Son doscientos bytes contra los cien kilobytes del recorrido, y
  /// son los que convierten esto en un respaldo de verdad — que es lo que
  /// Mauro pidió: «que la app pueda levantar un respaldo desde la base».
  Future<Resultado> subirRecorrido({
    required Credencial credencial,
    required String id,
    required String recorrido,
    required Map<String, dynamic> viaje,
    required int inicio,
    required int puntos,
    required String sello,
    GuardaDeSesion? sesion,
  }) async {
    return _escribir(
      credencial: credencial,
      coleccion: 'recorridos',
      id: id,
      sesion: sesion,
      que: 'El recorrido $id',
      campos: {
        'datos': {'stringValue': recorrido},
        'viaje': {'stringValue': jsonEncode(viaje)},
        // Sueltos para poder ordenar y mirar la colección sin abrir el texto.
        'inicio': {'integerValue': '$inicio'},
        'puntos': {'integerValue': '$puntos'},
        'sello': {'stringValue': sello},
      },
    );
  }

  /// Trae de vuelta el recorrido de un viaje, o `null` si no está.
  ///
  /// **Devuelve el texto crudo y no los puntos**: quien lo abre es
  /// `decodificarRecorrido`, que sabe decir por qué un recorrido no se puede
  /// leer. Mezclar las dos cosas acá haría que un problema de red y uno de
  /// formato se vieran igual.
  Future<Bajada> bajarRecorrido({
    required Credencial credencial,
    required String id,
    GuardaDeSesion? sesion,
  }) async {
    final token = await _tokenPara(credencial, sesion);
    if (token.falla != null) {
      return Bajada.mal(token.falla!, suya: token.suya);
    }
    try {
      final r = await cliente
          .get(
            Uri.parse(
              'https://firestore.googleapis.com/v1/projects/'
              '${credencial.proyecto}/databases/(default)/documents/'
              'recorridos/$id',
            ),
            headers: {'Authorization': 'Bearer ${token.valor}'},
          )
          .timeout(espera);
      if (r.statusCode == 404) return const Bajada.noEsta();
      if (r.statusCode == 403 || r.statusCode == 401) {
        return Bajada.mal(
          'La base no deja leer «recorridos» (${r.statusCode}). Revisá que '
          'las reglas publicadas sean las de `firestore.rules`: hasta la v0.9 '
          'el teléfono no podía leer nada.',
          suya: true,
        );
      }
      if (r.statusCode != 200) {
        return Bajada.mal('La base contestó ${r.statusCode}.');
      }
      final m = jsonDecode(r.body);
      final campos = m is Map ? m['fields'] : null;
      String? texto(String c) {
        final v = campos is Map ? campos[c] : null;
        final s = v is Map ? v['stringValue'] : null;
        return s is String ? s : null;
      }

      final datos = texto('datos');
      if (datos == null) {
        return Bajada.mal('Ese documento no tiene un recorrido adentro.');
      }
      return Bajada.bien(datos, ficha: texto('viaje'));
    } catch (e) {
      return Bajada.mal('No se pudo llegar a la base: $e');
    }
  }

  /// Qué recorridos hay en la nube. Devuelve `(id, inicio, puntos)` de cada
  /// uno, del más nuevo al más viejo.
  ///
  /// **No se baja el campo `datos`**: son cien kilobytes por viaje y para
  /// elegir uno de una lista no hace falta ninguno. Firestore deja pedir qué
  /// campos traer, y eso es lo que se hace.
  Future<List<RecorridoEnLaNube>> listarRecorridos({
    required Credencial credencial,
    GuardaDeSesion? sesion,
    int tope = 50,
  }) async {
    final token = await _tokenPara(credencial, sesion);
    if (token.falla != null) return const [];
    try {
      final campos = [
        'inicio',
        'puntos',
        'sello',
      ].map((c) => 'mask.fieldPaths=$c').join('&');
      final r = await cliente
          .get(
            Uri.parse(
              'https://firestore.googleapis.com/v1/projects/'
              '${credencial.proyecto}/databases/(default)/documents/'
              'recorridos?pageSize=$tope&$campos',
            ),
            headers: {'Authorization': 'Bearer ${token.valor}'},
          )
          .timeout(espera);
      if (r.statusCode != 200) return const [];
      final m = jsonDecode(r.body);
      final docs = m is Map ? m['documents'] : null;
      if (docs is! List) return const [];
      final salida = <RecorridoEnLaNube>[];
      for (final d in docs) {
        if (d is! Map) continue;
        final nombre = d['name'];
        final f = d['fields'];
        if (nombre is! String || f is! Map) continue;
        salida.add(
          RecorridoEnLaNube(
            id: nombre.split('/').last,
            inicio: _entero(f['inicio']),
            puntos: _entero(f['puntos']),
          ),
        );
      }
      salida.sort((a, b) => b.inicio.compareTo(a.inicio));
      return salida;
    } catch (_) {
      // Que no se pueda listar no es un error que valga la pena contar: la
      // pantalla muestra la lista vacía y el botón de subir sigue estando.
      return const [];
    }
  }

  /// Firestore devuelve los enteros como texto. Sí, de verdad.
  static int _entero(Object? v) {
    final s = v is Map ? v['integerValue'] : null;
    return s is String ? (int.tryParse(s) ?? 0) : 0;
  }

  /// El POST con todo lo que las dos subidas comparten, para que no haya dos
  /// copias del manejo de errores ni del login.
  Future<Resultado> _escribir({
    required Credencial credencial,
    required String coleccion,
    required String id,
    required Map<String, dynamic> campos,
    required String que,
    GuardaDeSesion? sesion,
  }) async {
    final token = await _tokenPara(credencial, sesion);
    if (token.falla != null) {
      return Resultado.mal(token.falla, esCulpaNuestra: token.suya);
    }
    try {
      final r = await cliente
          .post(
            Uri.parse(
              'https://firestore.googleapis.com/v1/projects/'
              '${credencial.proyecto}/databases/(default)/documents/'
              '$coleccion?documentId=$id',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${token.valor}',
            },
            body: jsonEncode({'fields': campos}),
          )
          .timeout(espera);

      if (r.statusCode == 200) {
        bitacora.anotar(Origen.sistema, '$que subió.');
        return const Resultado.bien();
      }
      // 409 es que ya estaba: no es una falla, es que no hacía falta.
      if (r.statusCode == 409) {
        bitacora.anotar(Origen.sistema, '$que ya estaba.');
        return const Resultado.bien();
      }
      if (r.statusCode == 403 || r.statusCode == 401) {
        return Resultado.mal(
          'La base rechazó la escritura (${r.statusCode}). Revisá que las '
          'reglas dejen crear en «$coleccion» a este usuario.',
          esCulpaNuestra: true,
        );
      }
      return Resultado.mal('La base contestó ${r.statusCode}.');
    } catch (e) {
      return Resultado.mal('No se pudo llegar a la base: $e');
    }
  }

  /// El token, o el motivo por el que no lo hay, en las mismas palabras para
  /// todos los caminos.
  ///
  /// **`suya` distingue las dos cosas que se ven igual y se tratan al revés.**
  /// Que falte la configuración o que la contraseña esté mal no se arregla
  /// insistiendo: la cola tiene que parar. Que no haya señal es el caso normal
  /// de una camioneta y se reintenta. Meterlas en la misma bolsa haría que un
  /// viaje en un lugar sin antena saliera de la cola como si no tuviera
  /// arreglo — o sea, perderlo. Hay dos pruebas que lo cuidan, y las dos
  /// fallaron cuando esto estuvo mal un rato.
  Future<({String? valor, String? falla, bool suya})> _tokenPara(
    Credencial credencial,
    GuardaDeSesion? sesion,
  ) async {
    final listo =
        credencial.completa ||
        (credencial.identificaProyecto && (sesion?.hay ?? false));
    if (!listo) {
      return (
        valor: null,
        falla: 'Todavía no está configurada la nube.',
        suya: true,
      );
    }
    try {
      final t = await _entrar(credencial, sesion);
      if (t == null) {
        return (
          valor: null,
          falla: 'El usuario o la contraseña de la nube no son correctos.',
          suya: true,
        );
      }
      return (valor: t, falla: null, suya: false);
    } catch (e) {
      // Sin señal, DNS que no resuelve, tiempo agotado.
      return (
        valor: null,
        falla: 'No se pudo llegar a la base: $e',
        suya: false,
      );
    }
  }

  void cerrar() => cliente.close();
}

/// Lo que hay de un viaje en la nube, sin el recorrido adentro.
class RecorridoEnLaNube {
  final String id;

  /// El instante en que arrancó el viaje. **Es la llave natural**, la misma
  /// con la que la importación reconoce un viaje repetido: sirve para cruzar
  /// lo que está arriba con lo que está en el teléfono sin depender del
  /// número local, que cambia.
  final int inicio;
  final int puntos;

  const RecorridoEnLaNube({
    required this.id,
    required this.inicio,
    required this.puntos,
  });
}

/// Cómo salió un intento de traer algo de la nube.
class Bajada {
  /// El texto que vino, si vino.
  final String? texto;

  /// Por qué no vino. `null` si vino, o si simplemente no estaba.
  final String? falla;

  /// El documento no existe. No es una falla: es que ese viaje no se subió.
  final bool noEstaba;

  /// Que insistir no va a servir: falta configurar, o las reglas no dejan.
  final bool esCulpaNuestra;

  /// La ficha del viaje —kilómetros, cortes, odómetro—, serializada. Puede
  /// faltar en un recorrido subido antes de que esto existiera.
  final String? ficha;

  const Bajada.bien(String this.texto, {this.ficha})
    : falla = null,
      noEstaba = false,
      esCulpaNuestra = false;

  const Bajada.noEsta()
    : texto = null,
      ficha = null,
      falla = null,
      noEstaba = true,
      esCulpaNuestra = false;

  const Bajada.mal(this.falla, {bool suya = false})
    : texto = null,
      ficha = null,
      noEstaba = false,
      esCulpaNuestra = suya;

  bool get hay => texto != null;
}
