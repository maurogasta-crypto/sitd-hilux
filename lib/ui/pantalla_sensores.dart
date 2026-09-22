import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../features/odometro/fuente.dart';
import '../features/odometro/fuente_gps.dart';
import '../core/bitacora.dart';
import '../features/permisos/avisos.dart';
import '../features/odometro/modo_recordado.dart';
import '../features/sensores/satelites.dart';
import '../features/odometro/integrador.dart';
import '../features/odometro/muestra.dart';
import '../features/odometro/servicio.dart';
import '../features/sensores/sensores.dart';
import 'formato.dart';
import '../core/db/base.dart';
import 'pantalla_calidad.dart';

/// Qué ve el teléfono, ahora mismo, y en qué estado está cada sensor.
///
/// **Es la pantalla de diagnóstico que faltaba.** Un viaje de siete minutos que
/// termina en cero kilómetros tiene media docena de causas posibles —el GPS no
/// fijó, llegó sin velocidad, la precisión no pasó el filtro, el permiso quedó
/// en «aproximada»— y desde afuera todas se ven igual: un cero. Acá cada
/// sensor dice si está entregando, a qué frecuencia y qué valor, y el GPS dice
/// además por qué se descarta lo que se descarta.
///
/// **Sobre el GPS hay una regla que no se puede romper:** una sola suscripción
/// a la vez. Si hay un viaje midiendo, esta pantalla mira lo que ya tiene el
/// servicio; si no, abre la suya y la cierra al salir. Dos suscripciones son
/// dos veces la misma batería, y el receptor no entrega el doble por eso.
class PantallaSensores extends StatefulWidget {
  final ServicioOdometria servicio;

  /// La escucha del motor GNSS de la aplicación. Se comparte en vez de armar
  /// una acá: el canal nativo es uno solo, y apagar el de esta pantalla
  /// apagaba el de todos.
  final Satelites? satelites;

  /// El modo de GPS que entregó la última vez, para que el selector arranque
  /// ahí y no en uno que ya se sabe que no anda en este teléfono.
  final ModoRecordado? modoRecordado;

  /// La base, para poder abrir «Probar la medición» desde acá.
  ///
  /// Opcional: sin ella la pantalla es la de siempre y el botón no aparece.
  final Base? base;

  const PantallaSensores({
    super.key,
    required this.servicio,
    this.satelites,
    this.modoRecordado,
    this.base,
  });

  @override
  State<PantallaSensores> createState() => _PantallaSensoresState();
}

class _PantallaSensoresState extends State<PantallaSensores> {
  final _gps = MedidorDeFrecuencia();
  final _acelerometro = MedidorDeFrecuencia();
  final _sinGravedad = MedidorDeFrecuencia();
  final _giroscopo = MedidorDeFrecuencia();
  final _magnetometro = MedidorDeFrecuencia();
  final _barometro = MedidorDeFrecuencia();

  final _suscripciones = <StreamSubscription<dynamic>>[];
  StreamSubscription<Lectura>? _gpsPropio;

  AccelerometerEvent? _ultimoAcelerometro;
  UserAccelerometerEvent? _ultimoSinGravedad;
  GyroscopeEvent? _ultimoGiroscopo;
  MagnetometerEvent? _ultimoMagnetometro;
  BarometerEvent? _ultimoBarometro;
  Muestra? _crudaPropia;
  MotivoDescarte? _motivoPropio;
  Disponibilidad? _problemaGps;
  DiagnosticoGps? _diagnostico;

  /// Cómo está el permiso de notificaciones. Se MIRA, no se pide: esta
  /// pantalla informa y no interrumpe con un diálogo a quien vino a ver
  /// números.
  EstadoAviso? _aviso;

  /// Lo que ve la ANTENA. Es lo último que faltaba: hasta acá todo lo que la
  /// pantalla sabía era del lado de la aplicación, y con el permiso dado, la
  /// ubicación encendida y cero posiciones ya no quedaba nada que preguntar
  /// desde Dart. Ver `satelites.dart`.
  /// La escucha del motor GNSS **compartida**, la que armó `Arranque`.
  ///
  /// **Antes esta pantalla se creaba la suya y la apagaba al salir**, y como el
  /// canal nativo es uno solo, eso apagaba la escucha de toda la aplicación:
  /// el reporte del 2026-09-19 salió con 30 satélites a la vista y
  /// `enganchado: false`. Se comparte y no se apaga desde acá.
  Satelites get _satelites => widget.satelites ?? _propia;
  late final Satelites _propia = Satelites();
  EstadoSatelites _cielo = const EstadoSatelites();

  /// Cuántas posiciones llegaron sin velocidad en la suscripción de esta
  /// pantalla, y con cuánto error venía la última.
  int _sinDopplerPropio = 0;
  double? _precisionPropia;

  /// En qué anda el enganche al GPS de esta pantalla. Sin esto, «Esperando»
  /// puede querer decir tres cosas distintas —todavía preguntando el permiso,
  /// ya suscripto y en silencio, o ni siquiera intentado— y las tres se veían
  /// exactamente igual.
  String _pasoGps = 'arrancando';

  /// Con qué modo arranca el selector.
  ///
  /// **No es `normal` a secas**, y ésa fue la incoherencia que encontró Mauro
  /// el 2026-09-19: el viaje medía perfecto y esta pantalla, al lado, no
  /// mostraba una sola lectura. El viaje bajaba de escalón solo —la cascada—
  /// y esta pantalla se quedaba clavada en `normal`, que en este teléfono no
  /// entrega. La pantalla que existe para diagnosticar estaba usando el modo
  /// roto mientras la aplicación ya había aprendido cuál andaba.
  late ModoGps _modo = widget.modoRecordado?.modo ?? ModoGps.normal;
  FuenteGps? _fuentePropia;
  int _desdeElModo = 0;

  late final int _desde = DateTime.now().millisecondsSinceEpoch;
  Timer? _refresco;

  int get _ahora => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _desdeElModo = _ahora;

    // **No se repinta con cada lectura.** El acelerómetro entrega cincuenta
    // veces por segundo: un `setState` por muestra son cincuenta
    // reconstrucciones del árbol por segundo en un Helio G85, que es el
    // teléfono de destino. Los datos se guardan al vuelo y la pantalla se
    // redibuja dos veces por segundo, que es más rápido de lo que un ojo
    // distingue.
    _refresco = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      // Se relee acá y no en un canal de eventos aparte: la pantalla ya se
      // redibuja dos veces por segundo, y una segunda cadencia para el mismo
      // dibujo sería gastar batería en un Helio G85 para no ver más rápido.
      final cielo = await _satelites.leer();
      if (!mounted) return;
      setState(() => _cielo = cielo);
    });

    _suscripciones.addAll([
      accelerometerEventStream().listen((e) {
        _ultimoAcelerometro = e;
        _acelerometro.anotar(_ahora);
      }, onError: (Object _) {}),
      userAccelerometerEventStream().listen((e) {
        _ultimoSinGravedad = e;
        _sinGravedad.anotar(_ahora);
      }, onError: (Object _) {}),
      gyroscopeEventStream().listen((e) {
        _ultimoGiroscopo = e;
        _giroscopo.anotar(_ahora);
      }, onError: (Object _) {}),
      magnetometerEventStream().listen((e) {
        _ultimoMagnetometro = e;
        _magnetometro.anotar(_ahora);
      }, onError: (Object _) {}),
      barometerEventStream().listen((e) {
        _ultimoBarometro = e;
        _barometro.anotar(_ahora);
      }, onError: (Object _) {}),
    ]);

    _engancharGps();
  }

  /// Si no hay viaje midiendo, esta pantalla escucha el GPS por su cuenta —y
  /// sólo mientras está abierta.
  ///
  /// **Y lo hace de tres formas distintas, a elección.** El 2026-09-16 el
  /// receptor no entregó ni una posición a cielo abierto, dos veces, con cero
  /// lecturas: ni siquiera descartadas. Con cero, el problema está antes del
  /// filtro — o del permiso, o de cómo se le pide al sistema. Cada modo saca
  /// una pieza del medio, y el que entregue dice cuál era.
  Future<void> _engancharGps() async {
    if (widget.servicio.estado.value.midiendo) return;

    setState(() => _pasoGps = 'preguntando permiso y última posición');
    final fuente = FuenteGps(modo: _modo);
    _fuentePropia = fuente;

    // Lo que se puede saber ANTES de la primera posición, que es justamente lo
    // que faltaba: el permiso con su nombre, si la ubicación del sistema está
    // encendida, y si el sistema tiene una última posición conocida.
    final diagnostico = await fuente.diagnosticar();
    final aviso = await mirarAvisoDelSistema();
    final cielo = await _satelites.arrancar();
    if (!mounted) return;
    setState(() {
      _diagnostico = diagnostico;
      _aviso = aviso;
      _cielo = cielo;
    });

    final disponible = await fuente.preparar();
    if (!mounted) return;
    if (!disponible.puedeArrancar) {
      setState(() {
        _problemaGps = disponible;
        _pasoGps = 'no se pudo arrancar';
      });
      return;
    }
    setState(() {
      _problemaGps = null;
      _pasoGps = 'suscripto, esperando que el receptor entregue';
      _desdeElModo = _ahora;
    });

    _gpsPropio = fuente.lecturas.listen(
      (l) {
        final m = l.muestra;
        // El contador cuenta toda lectura, traiga velocidad o no: una
        // posición sin Doppler es el receptor hablando. Lo que faltaba era
        // decir cuántas de esas no servían y con qué error venían.
        _gps.anotar(_ahora);
        _sinDopplerPropio = l.sinDoppler
            ? _sinDopplerPropio + 1
            : _sinDopplerPropio;
        if (l.precisionCruda != null) _precisionPropia = l.precisionCruda;
        if (m != null) {
          _crudaPropia = m;
          _motivoPropio = porQueNoSirve(m, widget.servicio.criterios);
        } else {
          _motivoPropio = null;
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(
            () => _problemaGps = Disponibilidad(MotivoGps.falla, detalle: '$e'),
          );
        }
      },
    );
  }

  /// Cambiar de modo corta la suscripción anterior antes de abrir la nueva:
  /// **al GPS se lo escucha una vez y nada más.**
  Future<void> _cambiarModo(ModoGps modo) async {
    await _gpsPropio?.cancel();
    _gpsPropio = null;
    await _fuentePropia?.detener();
    _gps.reiniciar();
    setState(() {
      _modo = modo;
      _desdeElModo = _ahora;
      _crudaPropia = null;
      _motivoPropio = null;
      _problemaGps = null;
    });
    await _engancharGps();
  }

  @override
  void dispose() {
    _refresco?.cancel();
    for (final s in _suscripciones) {
      s.cancel();
    }
    _gpsPropio?.cancel();
    _fuentePropia?.detener();
    // Sólo se apaga la propia, si es que hubo que armar una: la compartida la
    // sigue usando el resto de la aplicación.
    if (widget.satelites == null) _propia.detener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = widget.servicio.estado.value;
    final enViaje = e.midiendo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensores'),
        actions: [
          if (widget.base != null)
            IconButton(
              tooltip: 'Probar la medición',
              icon: const Icon(Icons.speed_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PantallaCalidad(base: widget.base!),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _Gps(
            enViaje: enViaje,
            estado: e,
            medidor: _gps,
            cruda: enViaje ? e.ultimaCruda : _crudaPropia,
            motivo: enViaje ? e.ultimoMotivo : _motivoPropio,
            problema: enViaje ? e.problema : _problemaGps,
            diagnostico: _diagnostico,
            aviso: _aviso,
            sinDoppler: enViaje ? e.sinDoppler : _sinDopplerPropio,
            precisionSinDoppler: enViaje
                ? e.precisionSinDoppler
                : _precisionPropia,
            paso: _pasoGps,
            modo: _modo,
            alCambiarModo: enViaje ? null : _cambiarModo,
            desde: enViaje ? _desde : _desdeElModo,
            ahora: _ahora,
            criterios: widget.servicio.criterios,
          ),
          const SizedBox(height: 12),
          _Cielo(cielo: _cielo),
          const SizedBox(height: 12),
          _Sensor(
            nombre: 'Acelerómetro',
            paraQue:
                'Es el titular del diagnóstico mecánico: de acá sale el '
                'espectro de vibración de cada viaje.',
            medidor: _acelerometro,
            desde: _desde,
            ahora: _ahora,
            valores: _ultimoAcelerometro == null
                ? const []
                : [
                    'x ${_ultimoAcelerometro!.x.toStringAsFixed(2)}  '
                        'y ${_ultimoAcelerometro!.y.toStringAsFixed(2)}  '
                        'z ${_ultimoAcelerometro!.z.toStringAsFixed(2)} m/s²',
                    'módulo ${_modulo(_ultimoAcelerometro!.x, _ultimoAcelerometro!.y, _ultimoAcelerometro!.z).toStringAsFixed(2)} m/s²'
                        ' · en reposo tiene que dar cerca de 9,8',
                  ],
          ),
          const SizedBox(height: 12),
          _Sensor(
            nombre: 'Acelerómetro sin gravedad',
            paraQue:
                'El mismo sensor con la gravedad ya descontada por el '
                'sistema. Todavía no se usa: sirve para comparar contra lo '
                'que descuenta la aplicación por su cuenta.',
            medidor: _sinGravedad,
            desde: _desde,
            ahora: _ahora,
            valores: _ultimoSinGravedad == null
                ? const []
                : [
                    'x ${_ultimoSinGravedad!.x.toStringAsFixed(2)}  '
                        'y ${_ultimoSinGravedad!.y.toStringAsFixed(2)}  '
                        'z ${_ultimoSinGravedad!.z.toStringAsFixed(2)} m/s²',
                  ],
          ),
          const SizedBox(height: 12),
          _Sensor(
            nombre: 'Giróscopo',
            paraQue:
                'Mide cuánto gira el teléfono. Sin uso todavía; puede '
                'servir para saber si el soporte se aflojó, o para separar '
                'una curva de un bache.',
            medidor: _giroscopo,
            desde: _desde,
            ahora: _ahora,
            valores: _ultimoGiroscopo == null
                ? const []
                : [
                    'x ${_ultimoGiroscopo!.x.toStringAsFixed(3)}  '
                        'y ${_ultimoGiroscopo!.y.toStringAsFixed(3)}  '
                        'z ${_ultimoGiroscopo!.z.toStringAsFixed(3)} rad/s',
                  ],
          ),
          const SizedBox(height: 12),
          _Sensor(
            nombre: 'Magnetómetro',
            paraQue:
                'La brújula. Adentro de una cabina hay hierro y '
                'corriente por todos lados, así que acá se lee sucia — y eso '
                'mismo se ve en el número.',
            medidor: _magnetometro,
            desde: _desde,
            ahora: _ahora,
            valores: _ultimoMagnetometro == null
                ? const []
                : [
                    'x ${_ultimoMagnetometro!.x.toStringAsFixed(1)}  '
                        'y ${_ultimoMagnetometro!.y.toStringAsFixed(1)}  '
                        'z ${_ultimoMagnetometro!.z.toStringAsFixed(1)} µT',
                    'módulo ${_modulo(_ultimoMagnetometro!.x, _ultimoMagnetometro!.y, _ultimoMagnetometro!.z).toStringAsFixed(1)} µT'
                        ' · el campo terrestre anda entre 25 y 65',
                  ],
          ),
          const SizedBox(height: 12),
          _Sensor(
            nombre: 'Barómetro',
            paraQue:
                'Presión del aire. Muchos teléfonos no lo tienen, y por '
                'eso es el mejor ejemplo de por qué existe esta pantalla: si '
                'no está, acá dice «no contesta» en vez de no decir nada.',
            medidor: _barometro,
            desde: _desde,
            ahora: _ahora,
            valores: _ultimoBarometro == null
                ? const []
                : ['${_ultimoBarometro!.pressure.toStringAsFixed(1)} hPa'],
          ),
          const SizedBox(height: 12),
          const _Bitacora(),
          const SizedBox(height: 16),
          Text(
            'Esta pantalla escucha los sensores sólo mientras está abierta, y '
            'los suelta al salir. El micrófono no aparece porque todavía no se '
            'pide su permiso: entra con la etapa E.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  static double _modulo(double x, double y, double z) {
    final s = x * x + y * y + z * z;
    return s <= 0 ? 0 : _raiz(s);
  }

  static double _raiz(double x) {
    var r = x;
    for (var i = 0; i < 20; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }
}

class _Sensor extends StatelessWidget {
  final String nombre;
  final String paraQue;
  final MedidorDeFrecuencia medidor;
  final List<String> valores;
  final int desde;
  final int ahora;

  const _Sensor({
    required this.nombre,
    required this.paraQue,
    required this.medidor,
    required this.valores,
    required this.desde,
    required this.ahora,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final estado = estadoDeSensor(
      suscripto: true,
      lecturas: medidor.lecturas,
      msDesdeQueArranco: ahora - desde,
      msDesdeLaUltima: medidor.ultimo == null ? null : ahora - medidor.ultimo!,
    );
    final hz = medidor.hz;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(nombre, style: t.textTheme.titleSmall)),
                _Chip(estado: estado),
              ],
            ),
            const SizedBox(height: 8),
            for (final v in valores)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(v, style: t.textTheme.bodyMedium),
              ),
            if (valores.isEmpty)
              Text(
                estado == EstadoSensor.mudo
                    ? 'No entregó ni una lectura. Puede que este teléfono no '
                          'lo tenga: Android no lo dice, simplemente no manda '
                          'nada.'
                    : 'Todavía no llegó nada.',
                style: t.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              '${medidor.lecturas} lecturas'
              '${hz == null ? "" : " · ${hz.toStringAsFixed(1)} Hz medidos"}'
              '${medidor.lecturas == 0 ? " · hace ${formatearDuracion(ahora - desde)} que no llega nada" : ""}',
              style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              paraQue,
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Gps extends StatelessWidget {
  final bool enViaje;
  final EstadoViaje estado;
  final MedidorDeFrecuencia medidor;
  final Muestra? cruda;
  final MotivoDescarte? motivo;
  final Disponibilidad? problema;
  final DiagnosticoGps? diagnostico;
  final EstadoAviso? aviso;

  /// Posiciones que llegaron SIN velocidad Doppler, y el error de la última.
  ///
  /// **Un viaje real registró 68 posiciones sin velocidad**, una cada 2,3
  /// segundos, y terminó en cero kilómetros. El contador de arriba las contaba
  /// —el receptor estaba hablando— pero nada decía que ninguna servía ni por
  /// qué. La precisión es lo que lo separa: arriba de cien metros es ubicación
  /// de red, que nunca trae velocidad; abajo de veinte es satélite sin
  /// resolverla todavía. Uno se arregla esperando y el otro no.
  final int sinDoppler;
  final double? precisionSinDoppler;
  final String paso;
  final ModoGps modo;
  final Future<void> Function(ModoGps)? alCambiarModo;
  final CriteriosGps criterios;
  final int desde;
  final int ahora;

  const _Gps({
    required this.enViaje,
    required this.estado,
    required this.medidor,
    required this.cruda,
    required this.motivo,
    required this.problema,
    required this.diagnostico,
    required this.aviso,
    required this.sinDoppler,
    required this.precisionSinDoppler,
    required this.paso,
    required this.modo,
    required this.alCambiarModo,
    required this.criterios,
    required this.desde,
    required this.ahora,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final o = estado.odometria;
    final lecturas = enViaje
        ? o.muestrasUsadas + o.muestrasDescartadas + estado.sinDoppler
        : medidor.lecturas;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('GPS', style: t.textTheme.titleSmall)),
                _Chip(
                  estado: problema != null
                      ? EstadoSensor.sinPermiso
                      : estadoDeSensor(
                          suscripto: true,
                          lecturas: lecturas,
                          msDesdeQueArranco: ahora - desde,
                          msDesdeLaUltima: cruda == null
                              ? null
                              : ahora - cruda!.t,
                          gracia: msDeGraciaGps,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (diagnostico != null) ...[
              // Lo que se sabe ANTES de la primera posición. Es la diferencia
              // entre «el receptor no fijó» y «el receptor anda pero esta
              // aplicación no lo está pidiendo bien».
              Text(
                'Permiso: ${diagnostico!.permiso} · ubicación del sistema: '
                '${diagnostico!.servicioEncendido ? "encendida" : "APAGADA"}'
                '${aviso == null ? "" : " · notificaciones: ${textoDeAviso(aviso!).toLowerCase()}"}',
                style: t.textTheme.bodySmall,
              ),
              Text(
                diagnostico!.ultimaConocida == null
                    ? 'El sistema no tiene ninguna posición conocida: el '
                          'receptor no fijó todavía, ni para esta aplicación '
                          'ni para ninguna otra.'
                    : 'El sistema SÍ tiene una última posición conocida '
                          '(${diagnostico!.ultimaConocida!.precision.toStringAsFixed(0)} m '
                          'de error): el receptor del teléfono funciona.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: diagnostico!.ultimaConocida == null
                      ? t.colorScheme.outline
                      : t.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (problema != null)
              Text(problema!.mensaje, style: t.textTheme.bodyMedium)
            else if (cruda == null)
              Text(
                'Todavía no llegó ninguna posición. Con cielo abierto tarda '
                'entre treinta segundos y un minuto.',
                style: t.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${cruda!.velocidad.isFinite ? (cruda!.velocidad * 3.6).toStringAsFixed(1) : "—"} km/h'
                ' · ${cruda!.precision.toStringAsFixed(0)} m de error',
                style: t.textTheme.bodyMedium,
              ),
              Text(
                'velocidad ±'
                '${cruda!.precisionVel == null ? "sin dato" : "${cruda!.precisionVel!.toStringAsFixed(1)} m/s"}'
                '${cruda!.alt == null ? "" : " · ${cruda!.alt!.toStringAsFixed(0)} m de altitud"}',
                style: t.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              // La posición NO se muestra, y es a propósito: la pantalla se
              // fotografía para pedir ayuda, y dónde está la camioneta no
              // tiene por qué viajar en esa foto.
              Text(
                motivo == null
                    ? 'La última sirve: entra a la odometría.'
                    : 'La última se descarta: ${_porQue(motivo!)}.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: motivo == null
                      ? t.colorScheme.primary
                      : t.colorScheme.error,
                ),
              ),
            ],
            if (enViaje && o.descartes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('En este viaje', style: t.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                '${o.muestrasUsadas} usadas · ${estado.sinDoppler} sin velocidad',
                style: t.textTheme.bodySmall,
              ),
              for (final d in o.descartes.entries)
                Text(
                  '${d.value} descartadas: ${_porQue(d.key)}',
                  style: t.textTheme.bodySmall,
                ),
              if (o.precisionTipicaDescartada > 0)
                Text(
                  'error típico de las descartadas: '
                  '${o.precisionTipicaDescartada.toStringAsFixed(0)} m '
                  '(se toleran hasta ${criterios.precisionMaxima.toStringAsFixed(0)})',
                  style: t.textTheme.bodySmall,
                ),
            ],
            if (sinDoppler > 0) ...[
              const SizedBox(height: 8),
              Text(
                precisionSinDoppler != null && precisionSinDoppler! > 100
                    ? '$sinDoppler posiciones llegaron SIN velocidad, con '
                          '${precisionSinDoppler!.toStringAsFixed(0)} m de '
                          'error: eso es ubicación de red —wifi y torres—, no '
                          'satélite. El receptor GPS todavía no fijó.'
                    : '$sinDoppler posiciones llegaron SIN velocidad'
                          '${precisionSinDoppler == null ? "" : " (${precisionSinDoppler!.toStringAsFixed(0)} m de error)"}'
                          '. El receptor habla; todavía no resuelve la '
                          'velocidad, que es de donde salen los kilómetros.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // El reloj es lo que saca la ambigüedad: «Esperando» a los tres
            // segundos y «Esperando» a los tres minutos son dos cosas muy
            // distintas, y sin el número se leen igual.
            Text(
              enViaje
                  ? '$lecturas posiciones en este viaje · el viaje está midiendo'
                  : '$lecturas posiciones'
                        '${medidor.hz == null ? "" : " · ${medidor.hz!.toStringAsFixed(2)} Hz medidos"}'
                        ' · ${formatearDuracion(ahora - desde)} en este modo'
                        '\n$paso',
              style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _porQue(MotivoDescarte m) => switch (m) {
    MotivoDescarte.precisionMala => 'el error de posición supera lo tolerado',
    MotivoDescarte.precisionVelMala =>
      'el receptor no le cree a su propia velocidad',
    MotivoDescarte.velocidadImplausible =>
      'velocidad imposible para una camioneta',
    MotivoDescarte.datoInvalido => 'números que no son números',
    MotivoDescarte.relojParaAtras => 'el reloj se repitió o fue para atrás',
  };
}

class _Chip extends StatelessWidget {
  final EstadoSensor estado;

  const _Chip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (color, icono) = switch (estado) {
      EstadoSensor.midiendo => (t.colorScheme.primary, Icons.check_circle),
      EstadoSensor.esperando => (t.colorScheme.outline, Icons.hourglass_bottom),
      EstadoSensor.mudo => (t.colorScheme.error, Icons.help_outline),
      EstadoSensor.cortado => (t.colorScheme.error, Icons.link_off),
      EstadoSensor.sinPermiso => (t.colorScheme.error, Icons.lock_outline),
      EstadoSensor.falla => (t.colorScheme.error, Icons.error_outline),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          nombreDeEstado(estado),
          style: t.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Lo que ve la antena, antes de que exista una posición.
///
/// **Es la tarjeta que contesta la pregunta que las otras no podían.** Con el
/// permiso dado, la ubicación encendida, las notificaciones concedidas y cero
/// posiciones en seis minutos, todo lo que se podía preguntar desde la
/// aplicación ya estaba contestado. Esto es el receptor contando satélites:
/// separa «los ve y no los puede resolver todavía» de «no ve ninguno», que se
/// arreglan de formas opuestas y hasta ahora se veían exactamente igual.
class _Cielo extends StatelessWidget {
  final EstadoSatelites cielo;

  const _Cielo({required this.cielo});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (color, icono, rotulo) = switch (cielo) {
      EstadoSatelites(disponible: false) => (
        t.colorScheme.outline,
        Icons.help_outline,
        'Sin datos',
      ),
      EstadoSatelites(huboPrimerFijado: true) => (
        t.colorScheme.primary,
        Icons.check_circle_outline,
        'Fijó',
      ),
      EstadoSatelites(vistos: 0) => (
        t.colorScheme.error,
        Icons.error_outline,
        'No ve nada',
      ),
      EstadoSatelites(usados: 0) => (
        t.colorScheme.tertiary,
        Icons.hourglass_empty,
        'Viendo, sin fijar',
      ),
      _ => (t.colorScheme.primary, Icons.check_circle_outline, 'Fijando'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Satélites', style: t.textTheme.titleMedium),
                ),
                Icon(icono, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  rotulo,
                  style: t.textTheme.labelLarge?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (cielo.disponible) ...[
              Text(
                'A la vista: ${cielo.vistos} · usados para fijar: '
                '${cielo.usados}',
                style: t.textTheme.bodyLarge,
              ),
              if (cielo.mejorCn0 > 0)
                Text(
                  'Mejor señal ${cielo.mejorCn0.toStringAsFixed(0)} dB-Hz · '
                  'arriba de 30 es usable, abajo de 25 se ve pero no alcanza',
                  style: t.textTheme.bodySmall,
                ),
              if (cielo.cn0.length > 1)
                Text(
                  'Las mejores: '
                  '${cielo.cn0.map((c) => c.toStringAsFixed(0)).join(" · ")}',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.outline,
                  ),
                ),
              Text(
                cielo.evento,
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(cielo.veredicto, style: t.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// El registro de lo que la aplicación le pidió al sistema y de lo que el
/// sistema contestó.
///
/// **Lo pidió Mauro, y el porqué es el que importa:** la pantalla dice en qué
/// estado está ahora, no cómo se llegó. Y mientras se maneja nadie puede
/// mirarla, así que lo que pasa durante un viaje —un cambio de escalón, un
/// error, el momento exacto en que el receptor habló— no lo ve nadie. Acá
/// queda, y viaja en el reporte para desarrollo.
class _Bitacora extends StatelessWidget {
  const _Bitacora();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<int>(
          valueListenable: bitacora.cambios,
          builder: (context, _, _) {
            final lineas = bitacora.alReves.take(40).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Bitácora con el sistema',
                        style: t.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${bitacora.cuantas}',
                      style: t.textTheme.labelLarge?.copyWith(
                        color: t.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Lo último arriba. Va entera en el reporte para desarrollo, '
                  'que es el que se puede mandar por un chat: acá no entra una '
                  'sola coordenada.',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                if (lineas.isEmpty)
                  Text('Todavía no pasó nada.', style: t.textTheme.bodySmall)
                else
                  for (final a in lineas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${_hora(a.t)}  ${nombreDeOrigen(a.origen)} · '
                        '${a.texto}',
                        style: t.textTheme.bodySmall,
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _hora(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, "0")}:'
        '${d.minute.toString().padLeft(2, "0")}:'
        '${d.second.toString().padLeft(2, "0")}';
  }
}
