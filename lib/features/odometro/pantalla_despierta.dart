import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/db/base.dart';

/// Mantener la pantalla encendida mientras se está midiendo.
///
/// **Salió de un viaje real**: la pantalla se apagaba sola cada pocos minutos
/// y había que desbloquear el teléfono para ver los kilómetros — manejando.
/// Eso es una distracción arriba de una camioneta de dos toneladas, y además
/// hacía imposible saber de un vistazo si el GPS estaba entregando.
///
/// **La contra está escrita y no se esconde:** el teléfono de la cabina vive
/// al sol y enchufado, y una pantalla encendida durante horas es calor que se
/// suma al del sol y a la carga. Por eso es un interruptor y no una decisión
/// tomada de antemano — y por eso el ajuste vive en la base, para que se
/// respete entre tandas.
class PantallaDespierta {
  final Base base;

  static const String _clave = 'pantalla_despierta';

  /// Se puede reemplazar en el banco de pruebas: el plugin de verdad necesita
  /// un teléfono, y esta lógica no.
  final Future<void> Function({required bool encendida}) aplicar;

  PantallaDespierta(
    this.base, {
    Future<void> Function({required bool encendida})? aplicar,
  }) : aplicar = aplicar ?? _wakelock;

  static Future<void> _wakelock({required bool encendida}) =>
      WakelockPlus.toggle(enable: encendida);

  /// Encendido por defecto: el caso normal es la camioneta enchufada y la
  /// pantalla a la vista. Quien quiera ahorrar calor lo apaga.
  bool get preferida => (base.leerAjuste(_clave) ?? 'si') == 'si';

  set preferida(bool valor) => base.escribirAjuste(_clave, valor ? 'si' : 'no');

  /// Lo llama el servicio al empezar, pausar y terminar un viaje.
  ///
  /// `midiendo` y la preferencia son dos cosas distintas: con la preferencia
  /// encendida pero sin viaje, la pantalla se apaga como siempre. **No se deja
  /// el teléfono despierto porque sí.**
  Future<void> segun({required bool midiendo}) async {
    try {
      await aplicar(encendida: midiendo && preferida);
    } catch (_) {
      // Si el sistema no deja, no pasa nada: la aplicación sigue midiendo. Es
      // una comodidad, no una pieza de la medición.
    }
  }
}
