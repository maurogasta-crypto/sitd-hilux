import 'dart:convert';

import 'package:flutter/services.dart';

/// El viaje, a la Pizarra de este mismo teléfono (`sitd-57`, `general:C4`
/// paso 1).
///
/// Mauro, 26-oct-2026: «que se pueda utilizar sin consumir datos… dentro del
/// mismo auto… y que pueda despertar al teléfono». La Hilux no sabe de redes:
/// le pasa a la Pizarra del Note 9, por su puerta local (`EnlaceProveedor` de
/// `pizarra`), el viaje en vivo cada 2 s y lo que pasa —empezó, terminó, una
/// línea fuera de lo normal—, y la Pizarra lo manda por Bluetooth o por el
/// wi-fi de la casa a la Pizarra del otro teléfono. Sin internet.
///
/// **Nunca lleva una coordenada.** La posición de la camioneta no sale por
/// acá: los mensajes se arman SÓLO con los constructores de abajo, y el banco
/// comprueba sus claves. Y la Pizarra los vuelve a filtrar al recibirlos.
///
/// **Nunca tira ni traba**: si la Pizarra no está instalada, no tiene el
/// enlace prendido o no reconoce la firma, contesta `false` y el viaje mide
/// igual. Después de tres «no» seguidos se deja de preguntar un minuto, para
/// no llamar al canal cada 2 s en un teléfono sin Pizarra.
class EnlaceConPizarra {
  EnlaceConPizarra({
    this.canal = const MethodChannel('uy.gasta.sitd_hilux/enlace'),
    int Function()? reloj,
  }) : _reloj = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  final MethodChannel canal;
  final int Function() _reloj;
  int _noSeguidos = 0;
  int _callarHasta = 0;

  /// Tres «no» seguidos y se calla esto.
  static const descansoMs = 60000;

  /// Manda [mensaje]. `true` si la Pizarra lo tomó.
  Future<bool> enviar(Map<String, Object> mensaje) async {
    final ahora = _reloj();
    if (ahora < _callarHasta) return false;
    bool ok;
    try {
      ok =
          await canal.invokeMethod<bool>('enviar', {
            'mensaje': jsonEncode(mensaje),
          }) ??
          false;
    } catch (_) {
      ok = false;
    }
    if (ok) {
      _noSeguidos = 0;
    } else if (++_noSeguidos >= 3) {
      _noSeguidos = 0;
      _callarHasta = ahora + descansoMs;
    }
    return ok;
  }
}

/// El viaje en vivo: la notificación quieta de la otra Pizarra
/// («🚙 82 km/h · 2.100 RPM · 5.ª · 34,2 km»).
Map<String, Object> mensajeVivo({
  double? kmh,
  required double km,
  double? rpm,
  int? marcha,
}) => {
  'tipo': 'vivo',
  if (kmh != null) 'kmh': (kmh * 10).round() / 10,
  'km': (km * 100).round() / 100,
  if (rpm != null) 'rpm': rpm.round(),
  'marcha': ?marcha,
};

/// Lo que pasa: suena en la otra Pizarra.
Map<String, Object> mensajeEvento(String titulo, String texto) => {
  'tipo': 'evento',
  'titulo': titulo,
  'texto': texto,
};

Map<String, Object> eventoEmpezo() =>
    mensajeEvento('🚙 Hilux · viaje empezado', 'La camioneta arrancó a medir.');

Map<String, Object> eventoTermino({required double km, required int ms}) =>
    mensajeEvento(
      '🚙 Hilux · viaje terminado',
      '${km.toStringAsFixed(1).replaceAll('.', ',')} km en '
          '${_duracion(ms)}.',
    );

Map<String, Object> eventoLinea(String texto) =>
    mensajeEvento('⚠️ Hilux · algo fuera de lo normal', texto);

String _duracion(int ms) {
  final min = (ms / 60000).round();
  if (min < 60) return '$min min';
  return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')} min';
}
