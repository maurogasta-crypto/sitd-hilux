import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/bitacora.dart';
import 'credencial.dart';

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

  /// Entra con mail y contraseña y devuelve el token, o `null`.
  Future<String?> _entrar(Credencial c) async {
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
    return m is Map ? m['idToken'] as String? : null;
  }

  /// Sube un reporte con el identificador [id].
  ///
  /// **No lanza nunca.** Que no haya señal es el caso normal en una camioneta,
  /// no un error: se devuelve el motivo y la cola reintenta.
  Future<Resultado> subir({
    required Credencial credencial,
    required String id,
    required Map<String, dynamic> reporte,
  }) async {
    if (!credencial.completa) {
      return const Resultado.mal(
        'Todavía no está configurada la nube.',
        esCulpaNuestra: true,
      );
    }
    try {
      final token = await _entrar(credencial);
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
