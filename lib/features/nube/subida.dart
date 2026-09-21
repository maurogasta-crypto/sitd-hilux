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

/// Sube un reporte a Firestore.
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
  Future<Resultado> subir({
    required Credencial credencial,
    required String id,
    required Map<String, dynamic> reporte,
    GuardaDeSesion? sesion,
  }) async {
    // Con una sesión viva alcanza con que la configuración identifique al
    // proyecto: la contraseña puede no estar, y ése es justamente el punto.
    final listo =
        credencial.completa ||
        (credencial.identificaProyecto && (sesion?.hay ?? false));
    if (!listo) {
      return const Resultado.mal(
        'Todavía no está configurada la nube.',
        esCulpaNuestra: true,
      );
    }
    try {
      final token = await _entrar(credencial, sesion);
      if (token == null) {
        return const Resultado.mal(
          'El usuario o la contraseña de la nube no son correctos.',
          esCulpaNuestra: true,
        );
      }

      final r = await cliente
          .post(
            Uri.parse(
              'https://firestore.googleapis.com/v1/projects/'
              '${credencial.proyecto}/databases/(default)/documents/reportes'
              '?documentId=$id',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'fields': {
                // El reporte entero, serializado. Ver el porqué arriba.
                'json': {'stringValue': jsonEncode(reporte)},
                // Dos campos sueltos para poder ordenar y mirar sin abrir el
                // texto. Nada más: lo que vale está adentro del `json`.
                'sello': {
                  'stringValue': '${(reporte['app'] as Map?)?['sello'] ?? ''}',
                },
                'generado': {'integerValue': '${reporte['generado'] ?? 0}'},
              },
            }),
          )
          .timeout(espera);

      if (r.statusCode == 200) {
        bitacora.anotar(Origen.sistema, 'Reporte $id subido.');
        return const Resultado.bien();
      }
      // 409 es que ya estaba: no es una falla, es que no hacía falta.
      if (r.statusCode == 409) {
        bitacora.anotar(Origen.sistema, 'El reporte $id ya estaba subido.');
        return const Resultado.bien();
      }
      if (r.statusCode == 403 || r.statusCode == 401) {
        return Resultado.mal(
          'La base rechazó la escritura (${r.statusCode}). Revisá que las '
          'reglas dejen crear en «reportes» a este usuario.',
          esCulpaNuestra: true,
        );
      }
      return Resultado.mal('La base contestó ${r.statusCode}.');
    } catch (e) {
      // Sin señal, DNS que no resuelve, tiempo agotado. Es el caso normal en
      // la camioneta y se reintenta después.
      return Resultado.mal('No se pudo llegar a la base: $e');
    }
  }

  void cerrar() => cliente.close();
}
