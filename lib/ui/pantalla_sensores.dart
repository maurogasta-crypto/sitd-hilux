import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../features/odometro/fuente.dart';
import '../features/odometro/integrador.dart';
import '../features/odometro/muestra.dart';
import '../features/odometro/servicio.dart';
import '../features/sensores/sensores.dart';

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

  const PantallaSensores({super.key, required this.servicio});

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

  late final int _desde = DateTime.now().millisecondsSinceEpoch;
  Timer? _refresco;

  int get _ahora => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();

    // **No se repinta con cada lectura.** El acelerómetro entrega cincuenta
    // veces por segundo: un `setState` por muestra son cincuenta
    // reconstrucciones del árbol por segundo en un Helio G85, que es el
    // teléfono de destino. Los datos se guardan al vuelo y la pantalla se
    // redibuja dos veces por segundo, que es más rápido de lo que un ojo
    // distingue.
    _refresco = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
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
  Future<void> _engancharGps() async {
    if (widget.servicio.estado.value.midiendo) return;
    final disponible = await widget.servicio.fuente.preparar();
    if (!mounted) return;
    if (!disponible.puedeArrancar) {
      setState(() => _problemaGps = disponible);
      return;
    }
    _gpsPropio = widget.servicio.fuente.lecturas.listen(
      (l) {
        final m = l.muestra;
        _gps.anotar(_ahora);
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

  @override
  void dispose() {
    _refresco?.cancel();
    for (final s in _suscripciones) {
      s.cancel();
    }
    _gpsPropio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = widget.servicio.estado.value;
    final enViaje = e.midiendo;

    return Scaffold(
      appBar: AppBar(title: const Text('Sensores')),
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
            desde: _desde,
            ahora: _ahora,
            criterios: widget.servicio.criterios,
          ),
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
              '${hz == null ? "" : " · ${hz.toStringAsFixed(1)} Hz medidos"}',
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
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            Text(
              enViaje
                  ? '$lecturas posiciones en este viaje · el viaje está midiendo'
                  : '$lecturas posiciones'
                        '${medidor.hz == null ? "" : " · ${medidor.hz!.toStringAsFixed(2)} Hz medidos"}'
                        ' · escuchando sólo mientras esta pantalla esté abierta',
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
