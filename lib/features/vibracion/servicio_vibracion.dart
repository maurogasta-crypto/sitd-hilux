import 'dart:async';
import 'dart:collection';

import '../../core/bitacora.dart';
import 'analisis.dart';
import 'fuente_vibracion.dart';
import 'postura.dart';
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

  /// El giróscopo, si hay (`sitd-42`). Sin él la ventana sale sin giro y todo
  /// lo demás igual.
  final FuenteDeGiro? giroscopo;

  /// Curvas y posición del teléfono. Vive mientras vive el servicio: el sesgo
  /// del giróscopo es del sensor y sirve de un viaje al siguiente.
  final Postura postura = Postura();

  /// De dónde sale la velocidad. Devuelve `null` si todavía no se sabe.
  final double? Function() velocidadKmh;

  /// La marcha que se OYE, si hay una tomada (`sitd-55`): con ella se miden
  /// las líneas del motor. Sin ella, sólo las de la rueda y el cardán.
  final int? Function()? marcha;

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
  double? _kmhInicial;

  /// Los últimos segundos del acelerómetro tal cual llegaron (`sitd-55`),
  /// para una grabación. A 200 Hz, 15 s son 3.000 sacudones: nada.
  final ListQueue<Sacudon> _crudo = ListQueue();
  static const int _msDeCrudo = 15000;
  int? _viaje;
  StreamSubscription<Sacudon>? _suscripcion;
  StreamSubscription<Giro>? _suscripcionGiro;

  /// La clase de muestreo de la última ventana, para anotar cuando el sistema
  /// le baja (o le sube) la frecuencia al acelerómetro.
  int? _claseAnterior;

  ServicioVibracion({
    required this.registro,
    required this.fuente,
    required this.velocidadKmh,
    this.marcha,
    this.giroscopo,
    this.duracionDeVentana = const Duration(seconds: 5),
    int Function()? reloj,
  }) : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  bool get midiendo => _suscripcion != null;

  void arrancar(int viaje) {
    if (midiendo) return;
    _viaje = viaje;
    guardadas = 0;
    descartadas = 0;
    _claseAnterior = null;
    postura.nuevoViaje();
    _reiniciar();
    try {
      _suscripcionGiro = giroscopo?.giros.listen(
        postura.giro,
        // Sin giróscopo —el Redmi 15— el stream falla o no emite: la
        // vibración sigue igual, sólo que sin curvas.
        onError: (Object _) => _suscripcionGiro?.cancel(),
      );
    } catch (_) {
      _suscripcionGiro = null;
    }
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
    final suscripcionGiro = _suscripcionGiro;
    _suscripcion = null;
    _suscripcionGiro = null;
    _viaje = null;
    _magnitud.clear();
    await suscripcion?.cancel();
    await suscripcionGiro?.cancel();
    await fuente.detener();
  }

  void _reiniciar() {
    _magnitud.clear();
    _tInicio = ahora();
    _cubetaInicial = _cubetaActual();
    _kmhInicial = velocidadKmh();
  }

  /// El acelerómetro crudo entre [desde] y [hasta] (ms), de lo que queda en
  /// memoria (los últimos 15 s).
  List<Sacudon> crudo(int desde, int hasta) => [
    for (final s in _crudo)
      if (s.t >= desde && s.t <= hasta) s,
  ];

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
      _kmhInicial = velocidadKmh();
    }
    _magnitud.add(s.magnitud);
    _crudo.addLast(s);
    while (_crudo.isNotEmpty && s.t - _crudo.first.t > _msDeCrudo) {
      _crudo.removeFirst();
    }
    postura.aceleracion(s);

    if (s.t - _tInicio < duracionDeVentana.inMilliseconds) return;

    final cubeta = _cubetaInicial;
    final alCerrar = _cubetaActual();
    final p = postura.cerrar(velocidadKmh());
    if (p.seMovio != null) {
      bitacora.anotar(
        Origen.sistema,
        'El teléfono se movió en el soporte: la gravedad se corrió '
        '${p.seMovio!.toStringAsFixed(0)}° durante '
        '${ventanasParaMovido * duracionDeVentana.inSeconds} s. Esas '
        'ventanas no se comparan.',
      );
    }

    // Sólo se guarda si la velocidad se mantuvo en la MISMA cubeta de punta a
    // punta. Una ventana que empieza a 58 y termina a 72 km/h mezcla dos
    // espectros distintos, y mezclados no se parecen a ninguno de los dos.
    if (cubeta != null && alCerrar == cubeta) {
      final kmhFin = velocidadKmh();
      final armada = armarVentana(
        magnitud: List<double>.from(_magnitud),
        tInicio: _tInicio,
        tFin: s.t,
        cubeta: cubeta,
        kmh: _kmhInicial != null && kmhFin != null
            ? (_kmhInicial! + kmhFin) / 2
            : kmhFin,
        marcha: marcha?.call(),
      );
      final v = armada?.con(giro: p.giro, angulo: p.angulo, movido: p.movido);
      if (v != null) {
        _anotarMuestreo(v.hz);
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

  /// Si el sistema le cambia la frecuencia al acelerómetro a mitad de viaje
  /// —el Note 9 la bajó de 50 a 12,6 Hz el 28-sep—, queda escrito. Sólo el
  /// cambio, no cada ventana.
  void _anotarMuestreo(double hz) {
    final clase = hz < hzMinimoParaComparar ? -1 : claseDeMuestreo(hz);
    if (clase == _claseAnterior) return;
    final antes = _claseAnterior;
    _claseAnterior = clase;
    bitacora.anotar(
      Origen.sistema,
      '${antes == null ? "El acelerómetro entrega" : "El acelerómetro pasó a"} '
      '${hz.toStringAsFixed(1)} Hz'
      '${clase == -1 ? " (no alcanza para comparar)" : ""}.',
    );
  }
}
