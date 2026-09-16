import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/bitacora.dart';

/// Lo que el receptor ve del cielo, aunque todavía no haya fijado nada.
@immutable
class EstadoSatelites {
  /// `false` cuando el canal nativo no contestó. No es un error: en una
  /// plataforma que no sea Android no existe, y la pantalla lo dice así.
  final bool disponible;

  /// `true` si la escucha está enganchada al sistema.
  final bool enganchado;

  /// Cuántos satélites tiene a la vista el receptor.
  final int vistos;

  /// De ésos, cuántos está usando para calcular la posición.
  final int usados;

  /// La mejor relación señal/ruido, en dB-Hz. Arriba de 30 es señal usable;
  /// entre 15 y 25 es un satélite que se ve pero no alcanza.
  final double mejorCn0;

  /// Las ocho mejores, para ver la forma y no un solo número.
  final List<double> cn0;

  /// Lo último que dijo el motor GNSS, con sus palabras.
  final String evento;

  /// Hace cuántos milisegundos, o `-1` si nunca dijo nada.
  final int msDelUltimo;

  /// `true` si alguna vez fijó, desde que arrancó la aplicación.
  final bool huboPrimerFijado;

  final String? falla;

  const EstadoSatelites({
    this.disponible = false,
    this.enganchado = false,
    this.vistos = 0,
    this.usados = 0,
    this.mejorCn0 = 0,
    this.cn0 = const [],
    this.evento = 'sin arrancar',
    this.msDelUltimo = -1,
    this.huboPrimerFijado = false,
    this.falla,
  });

  /// **La frase que separa los dos mundos**, y es para lo que existe toda esta
  /// pieza. Sin la cuenta de satélites, «el GPS no anda» puede querer decir
  /// dos cosas muy distintas que se arreglan de formas opuestas: una se
  /// arregla esperando quieto y la otra no se arregla con código.
  String get veredicto {
    if (!disponible) {
      return 'El teléfono no contestó la cuenta de satélites. No es un '
          'problema: el resto del diagnóstico sigue valiendo.';
    }
    if (!enganchado) return 'Todavía no se enganchó al motor GNSS.';
    if (huboPrimerFijado) {
      return 'El receptor ya fijó al menos una vez desde que abriste la '
          'aplicación: lo de acá en adelante no es un problema de antena.';
    }
    if (vistos == 0) {
      return 'El receptor NO ve un solo satélite. Eso no es efeméride vieja ni '
          'falta de paciencia: o está bajo techo de verdad, o la antena no '
          'está entregando. Ningún cambio en esta aplicación lo arregla.';
    }
    if (usados == 0) {
      return 'Ve $vistos satélites pero no usa ninguno todavía: los está '
          'viendo y no los puede resolver. Es exactamente lo que pasa en un '
          'arranque en frío con la efeméride vieja — el receptor tiene que '
          'bajarla de los propios satélites, y eso son varios minutos QUIETO '
          'y a cielo abierto, no treinta segundos.';
    }
    return 'Ve $vistos satélites y usa $usados: está fijando.';
  }

  /// Sin `falla`, que es texto del sistema y no tiene por qué viajar.
  Map<String, dynamic> aMapa() => {
    'disponible': disponible,
    'enganchado': enganchado,
    'vistos': vistos,
    'usados': usados,
    'mejorCn0': mejorCn0,
    'cn0': cn0,
    'evento': evento,
    'msDelUltimo': msDelUltimo,
    'huboPrimerFijado': huboPrimerFijado,
  };
}

/// El puente con el `GnssStatus` de Android.
///
/// **Es el único código nativo del proyecto**, y entró el 2026-09-16 porque
/// todo lo que se podía saber desde Dart ya estaba contestado: permiso dado,
/// ubicación encendida, notificaciones concedidas, suscripto, cero posiciones
/// en seis minutos y el sistema sin ninguna posición conocida. Un registro del
/// intercambio entre la aplicación y el sistema no agregaría nada — ese
/// intercambio es una llamada y después silencio. Lo que falta es lo que ve la
/// ANTENA, y eso sólo lo dice el sistema operativo.
class Satelites {
  final MethodChannel canal;

  Satelites({MethodChannel? canal})
    : canal = canal ?? const MethodChannel('uy.gasta.sitd_hilux/satelites');

  bool _arrancado = false;

  /// Engancha la escucha. **No lanza nunca**: si el canal no está, se devuelve
  /// «no disponible» y la aplicación sigue midiendo igual.
  Future<EstadoSatelites> arrancar() async {
    try {
      final ok = await canal.invokeMethod<bool>('arrancar') ?? false;
      _arrancado = ok;
      bitacora.anotar(
        Origen.satelites,
        ok
            ? 'Enganchado al motor GNSS del sistema.'
            : 'El sistema no dejó enganchar la cuenta de satélites.',
      );
      return await leer();
    } on MissingPluginException {
      bitacora.anotar(
        Origen.satelites,
        'El canal de satélites no existe en esta versión.',
      );
      return const EstadoSatelites(falla: 'el canal no está en esta versión');
    } catch (e) {
      bitacora.anotar(Origen.satelites, 'No se pudo enganchar: $e');
      return EstadoSatelites(falla: '$e');
    }
  }

  Future<EstadoSatelites> leer() async {
    if (!_arrancado) return const EstadoSatelites();
    try {
      final m = await canal.invokeMapMethod<String, dynamic>('leer');
      if (m == null) return const EstadoSatelites(falla: 'sin respuesta');
      final e = EstadoSatelites(
        disponible: true,
        enganchado: m['enganchado'] as bool? ?? false,
        vistos: m['vistos'] as int? ?? 0,
        usados: m['usados'] as int? ?? 0,
        mejorCn0: (m['mejorCn0'] as num? ?? 0).toDouble(),
        cn0: [for (final c in (m['cn0'] as List? ?? [])) (c as num).toDouble()],
        evento: m['evento'] as String? ?? '',
        msDelUltimo: m['msDelUltimo'] as int? ?? -1,
        huboPrimerFijado: m['huboPrimerFijado'] as bool? ?? false,
      );
      // Sin `anotarSiCambio` la bitácora se llena: el motor cuenta satélites
      // varias veces por segundo y casi siempre dice lo mismo.
      bitacora.anotarSiCambio(
        Origen.satelites,
        'Ve ${e.vistos}, usa ${e.usados}, mejor señal '
        '${e.mejorCn0.toStringAsFixed(0)} dB-Hz · ${e.evento}',
      );
      return e;
    } on MissingPluginException {
      return const EstadoSatelites(falla: 'el canal no está en esta versión');
    } catch (e) {
      return EstadoSatelites(falla: '$e');
    }
  }

  Future<void> detener() async {
    if (!_arrancado) return;
    _arrancado = false;
    try {
      await canal.invokeMethod<bool>('detener');
      bitacora.anotar(Origen.satelites, 'Escucha del motor GNSS soltada.');
    } catch (_) {
      // Soltar algo que ya estaba suelto no es un problema.
    }
  }
}
