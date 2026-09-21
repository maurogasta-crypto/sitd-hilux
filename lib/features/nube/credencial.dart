import 'dart:convert';

import '../../core/db/base.dart';

/// Lo que hace falta para escribir en la base remota.
///
/// ## Por qué NO está en el repositorio ni en el APK
///
/// **El repositorio es público y el APK se descarga sin cuenta** — comprobado
/// el 2026-09-19: `HTTP 206` contra el enlace del release, sin credencial
/// ninguna. Así que cualquiera puede bajar el APK y abrirlo, y **una
/// contraseña metida adentro no sería una contraseña: sería un dato público.**
///
/// Por eso la configuración **la teclea Mauro una vez, en el teléfono**, y
/// vive en el SQLite de la aplicación, que es privado de la aplicación. No
/// entra al repositorio, no entra a un chat, no entra al APK. La regla de oro
/// del proyecto queda intacta: acá se documenta el NOMBRE de cada campo y
/// dónde se pega, nunca el valor.
///
/// ## Por qué es un solo campo para pegar y no cuatro
///
/// Se trabaja desde un teléfono, y cada tanda obliga a desinstalar —lo que
/// borra la base y también esto—. Tipear cuatro campos en un teléfono después
/// de cada actualización es la clase de fricción que termina en «mejor no lo
/// uso». Con un solo pegado desde el gestor de contraseñas, es un toque.
class Credencial {
  /// El identificador del proyecto de Firebase.
  final String proyecto;

  /// La clave de API web del proyecto. **No es un secreto**: identifica al
  /// proyecto ante la API, igual que en los otros tres sitios del ecosistema.
  /// Lo que da o niega acceso son las reglas de Firestore.
  final String apiKey;

  /// El usuario del teléfono en Firebase Authentication. **Su contraseña sí es
  /// un secreto**, y por eso todo esto se teclea y no se versiona.
  final String mail;
  final String clave;

  const Credencial({
    required this.proyecto,
    required this.apiKey,
    required this.mail,
    required this.clave,
  });

  bool get completa =>
      proyecto.isNotEmpty &&
      apiKey.isNotEmpty &&
      mail.isNotEmpty &&
      clave.isNotEmpty;

  /// Lo mínimo para renovar una sesión ya abierta: sin la contraseña.
  ///
  /// Desde `sitd-19`, cuando hay un `refreshToken` guardado la contraseña deja
  /// de hacer falta — y deja de guardarse. Esto es lo que se exige entonces.
  bool get identificaProyecto =>
      proyecto.isNotEmpty && apiKey.isNotEmpty && mail.isNotEmpty;

  /// Lo que se muestra en pantalla. **Nunca incluye la contraseña**: la
  /// pantalla de ajustes es la que uno fotografía para pedir ayuda.
  String get resumen => '$mail → $proyecto';
}

/// La clave de `ajustes` donde vive la configuración de la nube.
///
/// Es pública porque `respaldo/saneado.dart` la necesita para sacarla de las
/// copias: si se renombra acá, el saneado la sigue sin que nadie se acuerde.
const String claveDeLaCredencial = 'nube_config';

/// Dónde vive la configuración de la nube: en `ajustes`, tecleada a mano.
class GuardaDeCredencial {
  final Base base;

  static const String _clave = claveDeLaCredencial;

  GuardaDeCredencial(this.base);

  /// Lo guardado, o `null` si todavía no se configuró.
  Credencial? get credencial {
    final crudo = base.leerAjuste(_clave);
    if (crudo == null || crudo.isEmpty) return null;
    return leerPegado(crudo);
  }

  bool get configurada => credencial?.completa ?? false;

  /// Guarda lo pegado. Devuelve `null` si estaba bien, o el motivo si no.
  String? guardar(String pegado) {
    final c = leerPegado(pegado);
    if (c == null) {
      return 'Eso no es la configuración. Tiene que ser el texto completo '
          'que empieza con «{» y termina con «}».';
    }
    if (!c.completa) {
      return 'Falta algún dato: hacen falta los cuatro (proyecto, apiKey, '
          'mail y clave).';
    }
    base.escribirAjuste(_clave, pegado.trim());
    return null;
  }

  /// Borra SÓLO la contraseña, dejando el resto de la configuración.
  ///
  /// Se llama después del primer login exitoso: a partir de ahí la sesión se
  /// renueva con el `refreshToken` y la contraseña no tiene por qué seguir
  /// viviendo en el teléfono. Si el token se revoca, la aplicación lo dice y
  /// hay que volver a configurarla — que es el precio, y es barato al lado de
  /// que lo que queda guardado deje de ser la cuenta entera.
  void olvidarClave() {
    final c = credencial;
    if (c == null) return;
    base.escribirAjuste(
      _clave,
      jsonEncode({
        'proyecto': c.proyecto,
        'apiKey': c.apiKey,
        'mail': c.mail,
        'clave': '',
      }),
    );
  }

  void olvidar() => base.escribirAjuste(_clave, '');
}

/// Entiende el texto que se pega. **No lanza nunca**: un pegado mal copiado
/// tiene que dar un mensaje, no una pantalla rota.
Credencial? leerPegado(String pegado) {
  try {
    final m = jsonDecode(pegado.trim());
    if (m is! Map) return null;
    return Credencial(
      proyecto: '${m['proyecto'] ?? ''}'.trim(),
      apiKey: '${m['apiKey'] ?? ''}'.trim(),
      mail: '${m['mail'] ?? ''}'.trim(),
      clave: '${m['clave'] ?? ''}'.trim(),
    );
  } catch (_) {
    return null;
  }
}

/// El molde para pegar, con los nombres de los campos y **ningún valor**.
/// Se muestra en la pantalla para que se vea qué forma tiene que tener.
const String moldeDeCredencial =
    '{\n'
    '  "proyecto": "",\n'
    '  "apiKey": "",\n'
    '  "mail": "",\n'
    '  "clave": ""\n'
    '}';
