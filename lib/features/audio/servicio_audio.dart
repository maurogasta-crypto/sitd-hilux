import 'dart:async';

import '../../core/bitacora.dart';
import 'compuerta.dart';
import 'regimen.dart';
import 'registro_audio.dart';

/// Lo que hay sonando en el teléfono, según el sistema.
typedef Ocupado = ({bool musica, bool llamada});

/// Escucha el micrófono durante un viaje y guarda una ventana cada tanto
/// (`sitd-37`, etapa E). Es el hermano de `ServicioVibracion`, con dos
/// diferencias que no son de forma:
///
///  - **Pasa por la compuerta** (`compuerta.dart`) antes de guardar: música,
///    llamada, velocidad, nivel. Lo que no pasa se cuenta por motivo.
///  - **Procesa un segundo de cada [cadaCuantos]**: un viaje de cinco horas
///    con una ventana por segundo serían 18.000 filas y un reporte que no
///    entra en un documento. Una cada cinco segundos alcanza para seguir las
///    RPM y son 720 por hora.
///
/// El sonido nunca sale de la memoria: cada trozo se resume y se suelta.
class ServicioAudio {
  final RegistroDeAudio registro;

  /// Abre el micrófono: trozos de un segundo de PCM de 16 bits.
  final Stream<List<int>> Function() abrir;

  /// Pregunta si hay música o una llamada. Si no contesta, se toma como que
  /// sí: lo que no se sabe cuenta como «no escuchar».
  final Future<Ocupado> Function() ocupado;

  final double? Function() velocidadKmh;
  final int cadaCuantos;
  final int Function() ahora;

  int guardadas = 0;
  final Map<MotivoAudio, int> descartes = {};

  /// Lo último que se escuchó con RPM, para la pantalla.
  double? ultimaRpm;
  int? ultimaRpmT;

  int? _viaje;
  int _trozos = 0;
  double? _kmhAnterior;
  StreamSubscription<List<int>>? _suscripcion;
  bool _ocupadoProcesando = false;

  ServicioAudio({
    required this.registro,
    required this.abrir,
    required this.ocupado,
    required this.velocidadKmh,
    this.cadaCuantos = 5,
    int Function()? reloj,
  }) : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  bool get escuchando => _suscripcion != null;

  void arrancar(int viaje) {
    if (escuchando) return;
    _viaje = viaje;
    _trozos = 0;
    _kmhAnterior = null;
    guardadas = 0;
    descartes.clear();
    try {
      _suscripcion = abrir().listen(
        _recibir,
        onError: (Object e) {
          // Un micrófono que falla no puede tirar abajo el viaje: lo que no se
          // puede perder es la odometría.
          bitacora.anotar(Origen.sistema, 'El micrófono dejó de entregar: $e');
          detener();
        },
      );
      bitacora.anotar(
        Origen.sistema,
        'Micrófono escuchando (una ventana cada $cadaCuantos s).',
      );
    } catch (e) {
      bitacora.anotar(Origen.sistema, 'El micrófono no abrió: $e');
      _suscripcion = null;
    }
  }

  /// Igual que la vibración: primero se sueltan los campos, después se espera.
  Future<void> detener() async {
    final s = _suscripcion;
    _suscripcion = null;
    _viaje = null;
    await s?.cancel();
  }

  Future<void> _recibir(List<int> pcm) async {
    final viaje = _viaje;
    if (viaje == null) return;
    final kmh = velocidadKmh();
    final alEmpezar = _kmhAnterior;
    _kmhAnterior = kmh;
    _trozos++;
    if ((_trozos - 1) % cadaCuantos != 0 || _ocupadoProcesando) return;
    _ocupadoProcesando = true;
    try {
      Ocupado o;
      try {
        o = await ocupado();
      } catch (_) {
        o = (musica: true, llamada: true);
      }
      final lectura = leerMotor(pcm);
      final motivo = compuerta(
        musica: o.musica,
        llamada: o.llamada,
        kmh: kmh,
        kmhAlEmpezar: alEmpezar,
        nivelDb: lectura.nivelDb,
        saturadas: lectura.saturadas,
      );
      if (motivo != MotivoAudio.abre || _viaje != viaje) {
        descartes[motivo] = (descartes[motivo] ?? 0) + 1;
        return;
      }
      final t = ahora();
      registro.guardar(viaje, VentanaAudio.de(lectura, t: t, kmh: kmh!));
      guardadas++;
      if (lectura.rpm != null) {
        ultimaRpm = lectura.rpm;
        ultimaRpmT = t;
      }
    } finally {
      _ocupadoProcesando = false;
    }
  }

  /// En palabras, para la pantalla: por qué no se está escuchando.
  String get resumen {
    if (!escuchando) return 'apagado';
    if (descartes.isEmpty && guardadas == 0) return 'escuchando';
    final peor = descartes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final motivo = peor.isEmpty
        ? ''
        : ' · más que nada: ${peor.first.key.texto}';
    return '$guardadas guardadas$motivo';
  }
}
