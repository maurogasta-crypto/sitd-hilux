import 'dart:async';

import 'fuente_vibracion.dart';
import 'registro_vibracion.dart';
import 'ventana.dart';

/// Junta sacudones hasta llenar una ventana, la resume y la guarda.
///
/// **La cubeta se decide con la velocidad del GPS**, que es la otra mitad del
/// asunto: un espectro sin saber a qué velocidad se tomó no sirve para nada.
/// Por eso este servicio no lee el GPS —no quiere una segunda suscripción—,
/// sino que le pregunta al de odometría a cuánto va, cada vez que cierra una
/// ventana.
class ServicioVibracion {
  final RegistroDeVibracion registro;
  final FuenteDeVibracion fuente;

  /// De dónde sale la velocidad. Devuelve `null` si todavía no se sabe.
  final double? Function() velocidadKmh;

  /// Cuánto dura una ventana. Cinco segundos a 50 Hz son 250 muestras: una
  /// resolución de 0,2 Hz, que separa de sobra lo que hay que separar, y un
  /// tramo lo bastante corto como para que la velocidad no cambie de cubeta
  /// adentro de él.
  final Duration duracionDeVentana;

  final int Function() ahora;

  /// Ventanas guardadas y descartadas en este viaje, para poder mostrarlo.
  int guardadas = 0;
  int descartadas = 0;

  final List<double> _magnitud = [];
  int _tInicio = 0;
  int? _cubetaInicial;
  int? _viaje;
  StreamSubscription<Sacudon>? _suscripcion;

  ServicioVibracion({
    required this.registro,
    required this.fuente,
    required this.velocidadKmh,
    this.duracionDeVentana = const Duration(seconds: 5),
    int Function()? reloj,
  }) : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  bool get midiendo => _suscripcion != null;

  void arrancar(int viaje) {
    if (midiendo) return;
    _viaje = viaje;
    guardadas = 0;
    descartadas = 0;
    _reiniciar();
    _suscripcion = fuente.sacudones.listen(
      _recibir,
      onError: (Object _) {
        // Un acelerómetro que falla no puede tirar abajo el viaje: la odometría
        // es lo que no se puede perder. Se deja de juntar y listo.
        detener();
      },
    );
  }

  /// Corta y suelta el sensor.
  ///
  /// **Lo primero que se hace es soltar los campos, y recién después se
  /// espera la cancelación.** Al revés —`await` primero— la cancelación deja
  /// un hueco: entre el `await` y la línea siguiente, `midiendo` sigue diciendo
  /// que sí y un `arrancar()` que llegue ahí se va sin hacer nada. Lo encontró
  /// el banco, y era exactamente lo que iba a pasar en la pantalla al cerrar
  /// un viaje y empezar el siguiente enseguida.
  Future<void> detener() async {
    final suscripcion = _suscripcion;
    _suscripcion = null;
    _viaje = null;
    _magnitud.clear();
    await suscripcion?.cancel();
    await fuente.detener();
  }

  void _reiniciar() {
    _magnitud.clear();
    _tInicio = ahora();
    _cubetaInicial = _cubetaActual();
  }

  int? _cubetaActual() {
    final v = velocidadKmh();
    return v == null ? null : cubetaDe(v);
  }

  void _recibir(Sacudon s) {
    final viaje = _viaje;
    if (viaje == null) return;

    if (_magnitud.isEmpty) {
      _tInicio = s.t;
      _cubetaInicial = _cubetaActual();
    }
    _magnitud.add(s.magnitud);

    if (s.t - _tInicio < duracionDeVentana.inMilliseconds) return;

    final cubeta = _cubetaInicial;
    final alCerrar = _cubetaActual();

    // Sólo se guarda si la velocidad se mantuvo en la MISMA cubeta de punta a
    // punta. Una ventana que empieza a 58 y termina a 72 km/h mezcla dos
    // espectros distintos, y mezclados no se parecen a ninguno de los dos.
    if (cubeta != null && alCerrar == cubeta) {
      final v = armarVentana(
        magnitud: List<double>.from(_magnitud),
        tInicio: _tInicio,
        tFin: s.t,
        cubeta: cubeta,
      );
      if (v != null) {
        registro.guardar(viaje, v);
        guardadas++;
      } else {
        descartadas++;
      }
    } else {
      descartadas++;
    }
    _reiniciar();
  }
}
