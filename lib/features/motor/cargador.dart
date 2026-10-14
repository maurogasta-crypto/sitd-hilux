import 'package:flutter/services.dart';

/// Un aviso del cargador: si está cargando, y si es el primero (cómo estaba
/// al empezar a escuchar) o un cambio.
typedef AvisoCarga = ({bool conectado, bool inicial});

/// El cargador del teléfono, por el canal de `MainActivity.kt` (`sitd-37`).
class CargadorDelTelefono {
  static const _eventos = EventChannel('uy.gasta.sitd_hilux/carga');

  Stream<AvisoCarga> avisos() => _eventos.receiveBroadcastStream().map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    return (conectado: m['conectado'] == true, inicial: m['inicial'] == true);
  });
}
