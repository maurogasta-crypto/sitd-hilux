import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'regimen.dart';
import 'servicio_audio.dart';

/// El micrófono y el estado del audio del sistema, por los canales de
/// `MainActivity.kt` (`sitd-37`). Es lo único de la etapa E que toca Android:
/// lo demás es Dart puro y lo corre el banco.
class MicrofonoDelTelefono {
  static const _eventos = EventChannel('uy.gasta.sitd_hilux/audio');
  static const _metodos = MethodChannel('uy.gasta.sitd_hilux/audio_estado');

  /// Trozos de un segundo de PCM de 16 bits, a [hzAudio]. Llegan como bytes
  /// (el codec de Flutter no lleva arreglos de 16 bits) y se leen de a dos.
  Stream<List<int>> trozos() => _eventos
      .receiveBroadcastStream({'hz': hzAudio})
      .map((e) => aMuestras(e as Uint8List));

  /// Con qué modo abrió el micrófono (`sitd-47`): «sin procesar» o «voz
  /// (…)». `null` si todavía no se abrió o el canal no contesta.
  Future<String?> fuente() async {
    try {
      return await _metodos.invokeMethod<String>('fuenteMicrofono');
    } catch (_) {
      return null;
    }
  }

  /// Si hay música o una llamada. Si el canal no contesta, tira: el servicio
  /// lo toma como «no escuchar».
  Future<Ocupado> ocupado() async {
    final m = await _metodos.invokeMapMethod<String, dynamic>('ocupado');
    return (musica: m?['musica'] == true, llamada: m?['llamada'] == true);
  }
}

/// Bytes PCM 16 bits little-endian → muestras.
List<int> aMuestras(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  return List<int>.generate(
    bytes.length ~/ 2,
    (i) => d.getInt16(i * 2, Endian.little),
  );
}
