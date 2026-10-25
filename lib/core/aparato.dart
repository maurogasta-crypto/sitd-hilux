import 'package:flutter/services.dart';

import 'db/base.dart';

/// En qué teléfono corre la aplicación (`sitd-44`, `hilux:D5`).
///
/// **Existe porque con dos o tres teléfonos un viaje tiene que poder decir de
/// dónde salió.** El 10-oct el Note 9 y el Redmi 15 midieron el mismo viaje y
/// dieron lo mismo, así que mezclar sus respaldos no ensucia nada; pero un
/// teléfono que muestree distinto (el 13C, a 63 Hz) sí, y sin el modelo al
/// lado no hay forma de saber de cuál vino un viaje sumado.
///
/// Se guarda en `ajustes`, que es de ESTE teléfono y no viaja en un respaldo
/// (`tablasQueNoSeImportan`): así un viaje nuevo lo toma de acá y nunca el de
/// otro aparato.
const String claveDelTelefono = 'telefono';

/// Pregunta el modelo por el canal de `MainActivity.kt` y lo deja en
/// `ajustes`. **Nunca tira**: si el canal no contesta, el viaje se guarda sin
/// teléfono, que es lo que ya pasaba —esto describe, no mide.
Future<void> anotarTelefono(
  Base base, {
  MethodChannel canal = const MethodChannel('uy.gasta.sitd_hilux/aparato'),
}) async {
  try {
    final modelo = textoDelTelefono(await canal.invokeMethod<String>('modelo'));
    if (modelo != null) base.escribirAjuste(claveDelTelefono, modelo);
  } catch (_) {
    // Otra plataforma, una versión vieja o el canal sin registrar: sin modelo.
  }
}

/// Limpia lo que contesta el sistema: sin espacios de más, sin repetir la
/// marca («Xiaomi Xiaomi 23100RN82L» → «Xiaomi 23100RN82L») y con techo.
String? textoDelTelefono(String? crudo) {
  final partes = (crudo ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (partes.isEmpty) return null;
  if (partes.length > 1 && partes[0].toLowerCase() == partes[1].toLowerCase()) {
    partes.removeAt(0);
  }
  final t = partes.join(' ');
  return t.length > 60 ? t.substring(0, 60) : t;
}
