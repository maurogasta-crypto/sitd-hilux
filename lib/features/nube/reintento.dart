import 'dart:io';

/// Volver a sincronizar cuando vuelve la señal (`sitd-55`).
///
/// Mauro, 26-oct: «quiero que la app intente hacer el respaldo cuando
/// arranque para sincronizarse o cuando tenga conexión». Al abrir y al cerrar
/// un viaje ya sincronizaba (`sitd-50`); lo que faltaba es el caso de la
/// camioneta: el viaje termina lejos de una antena, la sincronización falla,
/// y no se volvía a intentar hasta la próxima vez que alguien abriera la app.
///
/// Sin complemento nuevo a propósito: un complemento de conectividad es
/// código nativo, y el nativo es lo que el banco no ve (`README.md`,
/// «Verificación previa»). Se pregunta por la red con una consulta DNS al
/// mismo servidor al que se sube: si no contesta, no se intenta nada y no
/// se anota nada. Y si se intentó y falló, la próxima espera el doble —5,
/// 10, 20, 40 min y de ahí cada hora—: una falla que no es de señal (una
/// regla sin publicar) no puede bajar y subir copias enteras cada 5 minutos
/// por datos móviles.
class Reintento {
  /// La primera espera después de una falla.
  static const Duration primera = Duration(minutes: 5);

  /// La espera más larga entre dos intentos.
  static const Duration tope = Duration(minutes: 60);

  /// Cada cuánto se mira si toca (el reloj de la aplicación).
  static const Duration cadaCuanto = Duration(minutes: 1);

  final int Function() _ahora;

  Reintento({int Function()? reloj})
    : _ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  bool _fallo = false;
  Duration _espera = primera;
  int _desde = 0;

  /// Si la última sincronización quedó sin terminar bien.
  bool get pendiente => _fallo;

  /// Cuánto se va a esperar después de la falla actual.
  Duration get espera => _espera;

  /// Lo que dijo la última: con [salioBien] se vuelve a empezar de cero.
  void resultado({required bool salioBien}) {
    if (salioBien) {
      _fallo = false;
      _espera = primera;
      return;
    }
    if (_fallo) {
      final doble = _espera * 2;
      _espera = doble > tope ? tope : doble;
    }
    _fallo = true;
    _desde = _ahora();
  }

  /// Si toca intentar ahora: hubo una falla, o hay viajes esperando en la
  /// cola; ya pasó la espera; y no hay otra corriendo.
  bool toca({required int enCola, required bool corriendo}) {
    if (corriendo) return false;
    if (!_fallo && enCola == 0) return false;
    if (!_fallo) return true;
    return _ahora() - _desde >= _espera.inMilliseconds;
  }
}

/// Si hay red hasta la base: una consulta DNS, con su tiempo. Nunca tira.
Future<bool> hayRed({
  String servidor = 'firestore.googleapis.com',
  Duration espera = const Duration(seconds: 5),
}) async {
  try {
    final r = await InternetAddress.lookup(servidor).timeout(espera);
    return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
