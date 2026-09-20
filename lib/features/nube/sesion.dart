import '../../core/db/base.dart';

/// El `refreshToken` de Firebase, que es lo que reemplaza a guardar la
/// contraseña en el teléfono.
///
/// ## Por qué existe
///
/// Hasta `sitd-18` la aplicación guardaba la CONTRASEÑA en `ajustes` y la
/// mandaba en cada subida. Funcionaba, y tenía dos costos que no se ven hasta
/// que hacen falta:
///
///  - **No se puede revocar.** Si el teléfono se pierde, la única forma de
///    cortar el acceso es cambiar la contraseña — y eso la cambia también para
///    Mauro, en su propia base.
///  - **Es la credencial entera.** Quien saque el archivo del teléfono no se
///    lleva un permiso para subir reportes: se lleva la cuenta de esa base.
///
/// Firebase devuelve un `refreshToken` en el mismo login que ya se hacía, y el
/// código lo tiraba. Guardarlo en vez de la contraseña cambia las dos cosas:
/// **se revoca desde la consola sin tocar la contraseña**, y lo que queda en
/// el teléfono ya no abre nada más que esto.
///
/// ## Lo que NO cambia
///
/// Las reglas siguen siendo las mismas y siguen siendo la frontera real: el
/// teléfono sólo puede CREAR en `reportes/`. Esto no afloja nada — reduce qué
/// se lleva quien tenga el teléfono desbloqueado.
class GuardaDeSesion {
  final Base base;

  static const String _clave = 'nube_refresh';

  GuardaDeSesion(this.base);

  /// El token guardado, o `null` si todavía no se entró nunca.
  String? get token {
    final t = base.leerAjuste(_clave);
    return (t == null || t.isEmpty) ? null : t;
  }

  bool get hay => token != null;

  void guardar(String t) => base.escribirAjuste(_clave, t);

  /// Se olvida cuando el token deja de servir —revocado desde la consola, o
  /// caducado— para que el próximo intento vuelva a entrar con la contraseña
  /// en vez de reintentar para siempre contra un token muerto.
  void olvidar() => base.escribirAjuste(_clave, '');
}
