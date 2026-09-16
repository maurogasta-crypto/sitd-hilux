import 'package:permission_handler/permission_handler.dart';

/// En qué quedó el permiso de notificaciones.
enum EstadoAviso {
  /// Se puede mostrar la notificación del servicio en primer plano.
  concedido,

  /// Se negó, pero se puede volver a pedir.
  negado,

  /// Negado de forma permanente: desde la aplicación ya no se puede pedir.
  negadoParaSiempre,

  /// No se pudo averiguar. El detalle queda en el texto.
  sinAveriguar,
}

String textoDeAviso(EstadoAviso e) => switch (e) {
  EstadoAviso.concedido => 'Concedido',
  EstadoAviso.negado => 'Negado',
  EstadoAviso.negadoParaSiempre => 'Negado para siempre',
  EstadoAviso.sinAveriguar => 'Sin averiguar',
};

/// Pide el permiso de notificaciones, que es lo que hace VISIBLE la
/// notificación del servicio en primer plano.
///
/// **Por qué existe este archivo, y no es cosmética.** Desde Android 13 el
/// servicio en primer plano arranca igual sin este permiso, pero queda sin
/// cartel — y un servicio en primer plano invisible es justo lo que un Xiaomi
/// mata sin que nadie se entere. Hasta `sitd-10` el permiso estaba declarado
/// en el manifiesto y **nunca se pedía en tiempo de ejecución**, que es lo
/// único que lo concede: declararlo sin pedirlo no hace absolutamente nada.
///
/// Es además una de las explicaciones posibles del receptor que no entregó ni
/// una posición: si el sistema no deja mostrar la notificación, el servicio en
/// primer plano puede no llegar a arrancar, y el stream se queda callado sin
/// dar un error. Contra eso la red es la cascada de `cascada.dart`; esto es la
/// causa, no la red.
typedef PedirAviso = Future<EstadoAviso> Function();

/// La implementación de verdad, contra el sistema.
Future<EstadoAviso> pedirAvisoDelSistema() async {
  try {
    var estado = await Permission.notification.status;
    if (estado.isDenied) estado = await Permission.notification.request();
    if (estado.isGranted || estado.isLimited) return EstadoAviso.concedido;
    if (estado.isPermanentlyDenied) return EstadoAviso.negadoParaSiempre;
    return EstadoAviso.negado;
  } catch (_) {
    // Nunca lanza: que falte el cartel no puede impedir que se mida.
    return EstadoAviso.sinAveriguar;
  }
}

/// Lo mismo pero sin pedir nada: sólo mira cómo está. Es lo que usa la
/// pantalla de sensores, que informa y no interrumpe.
Future<EstadoAviso> mirarAvisoDelSistema() async {
  try {
    final estado = await Permission.notification.status;
    if (estado.isGranted || estado.isLimited) return EstadoAviso.concedido;
    if (estado.isPermanentlyDenied) return EstadoAviso.negadoParaSiempre;
    return EstadoAviso.negado;
  } catch (_) {
    return EstadoAviso.sinAveriguar;
  }
}
