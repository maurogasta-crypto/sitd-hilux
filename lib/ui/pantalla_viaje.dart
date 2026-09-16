import 'dart:async';

import 'package:flutter/material.dart';

import '../features/odometro/fuente.dart';
import '../features/odometro/registro.dart';
import '../features/odometro/servicio.dart';
import 'formato.dart';
import 'pantalla_diagnostico.dart';

/// La pantalla del viaje en curso.
///
/// Está pensada para mirarse de reojo desde el asiento: los kilómetros en
/// grande y todo lo demás chico. Lo que se toca —empezar, pausar, terminar—
/// son botones de 56 px, que es lo que se acierta con la camioneta en
/// movimiento y sin mirar.
class PantallaViaje extends StatefulWidget {
  final ServicioOdometria servicio;
  final RegistroDeViajes registro;
  final String ruta;

  const PantallaViaje({
    super.key,
    required this.servicio,
    required this.registro,
    required this.ruta,
  });

  @override
  State<PantallaViaje> createState() => _PantallaViajeState();
}

class _PantallaViajeState extends State<PantallaViaje> {
  /// El reloj de la duración avanza aunque no llegue una muestra. Sin esto,
  /// con el receptor callado la pantalla parecería congelada — y «no llega
  /// señal» tiene que verse distinto de «la aplicación se colgó».
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    _tic = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  Future<void> _empezar() async {
    final ok = await widget.servicio.arrancar();
    if (!ok && mounted) {
      final problema = widget.servicio.estado.value.problema;
      if (problema != null) _avisar(problema);
    }
  }

  void _avisar(Disponibilidad problema) {
    final detalle = problema.detalle;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          detalle == null
              ? problema.mensaje
              : '${problema.mensaje}\n\n$detalle',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _terminar() async {
    final viaje = widget.servicio.estado.value;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terminar el viaje'),
        // Una confirmación dice qué pasa exactamente, no «¿estás seguro?».
        content: Text(
          'Se cierra el viaje con ${formatearKm(viaje.kilometros)} y queda '
          'guardado. Las muestras del GPS no se borran: el viaje se puede '
          'volver a calcular cuando mejore el filtro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Seguir midiendo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
    if (confirma == true) await widget.servicio.terminar();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SITD Hilux'),
        actions: [
          IconButton(
            tooltip: 'Estado de la aplicación',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PantallaDiagnostico(
                  registro: widget.registro,
                  ruta: widget.ruta,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<EstadoViaje>(
        valueListenable: widget.servicio.estado,
        builder: (context, e, _) {
          final problema = e.problema;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _Tablero(estado: e),
              const SizedBox(height: 12),
              if (problema != null) ...[
                _Aviso(problema: problema),
                const SizedBox(height: 12),
              ],
              if (e.estadoDeLaSenal != null) ...[
                _Senal(texto: e.estadoDeLaSenal!),
                const SizedBox(height: 12),
              ],
              _Detalle(estado: e),
              const SizedBox(height: 12),
              Text(
                'La distancia sale de integrar la velocidad que informa el '
                'receptor, no de sumar posiciones. El haversine está al lado '
                'como control cruzado: si se separan mucho, hay que '
                'desconfiar de la señal.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: ValueListenableBuilder<EstadoViaje>(
          valueListenable: widget.servicio.estado,
          builder: (context, e, _) => Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: e.midiendo
                      ? FilledButton.tonalIcon(
                          onPressed: widget.servicio.pausar,
                          icon: const Icon(Icons.pause),
                          label: const Text('Pausar'),
                        )
                      : FilledButton.icon(
                          onPressed: _empezar,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            e.hayViaje ? 'Seguir el viaje' : 'Empezar el viaje',
                          ),
                        ),
                ),
              ),
              if (e.hayViaje) ...[
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _terminar,
                    icon: const Icon(Icons.stop),
                    label: const Text('Terminar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tablero extends StatelessWidget {
  final EstadoViaje estado;

  const _Tablero({required this.estado});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final v = estado.velocidadKmh;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatearKm(estado.kilometros),
              style: t.textTheme.displayMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  estado.midiendo ? Icons.gps_fixed : Icons.gps_off,
                  size: 18,
                  color: estado.midiendo
                      ? t.colorScheme.primary
                      : t.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  estado.midiendo
                      ? 'Midiendo'
                      : estado.hayViaje
                      ? 'En pausa'
                      : 'Sin viaje',
                  style: t.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  // «Todavía no sé» no se dibuja como un cero.
                  v == null ? '— km/h' : '${v.toStringAsFixed(0)} km/h',
                  style: t.textTheme.titleMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que pasa mientras no hay una sola muestra buena.
///
/// No es un error y no se pinta como uno: es el receptor haciendo su trabajo.
/// Lo que sí es, es la diferencia entre «esto todavía no agarró señal» y «esto
/// no anda», que sin este cartel se veían igual — las dos, un cero.
class _Senal extends StatelessWidget {
  final String texto;

  const _Senal({required this.texto});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      color: t.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: t.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final Disponibilidad problema;

  const _Aviso({required this.problema});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final detalle = problema.detalle;
    return Card(
      color: t.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              problema.mensaje,
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onErrorContainer,
              ),
            ),
            if (detalle != null) ...[
              const SizedBox(height: 8),
              Text(
                detalle,
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  final EstadoViaje estado;

  const _Detalle({required this.estado});

  @override
  Widget build(BuildContext context) {
    final o = estado.odometria;
    final inicio = estado.inicio;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Dato(
              titulo: 'Duración',
              valor: inicio == null
                  ? '—'
                  : formatearDuracion(
                      DateTime.now().millisecondsSinceEpoch - inicio,
                    ),
            ),
            _Dato(titulo: 'Muestras', valor: '${o.muestrasUsadas}'),
            _Dato(titulo: 'Descartadas', valor: '${o.muestrasDescartadas}'),
            _Dato(titulo: 'Sin velocidad', valor: '${estado.sinDoppler}'),
            _Dato(titulo: 'Cortes', valor: '${o.cortes}'),
            _Dato(
              titulo: 'Haversine',
              valor: formatearKm(o.metrosHaversine / 1000),
            ),
            _Dato(
              titulo: 'Discrepancia',
              valor: '${(o.discrepancia * 100).toStringAsFixed(1)} %',
            ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String titulo;
  final String valor;

  const _Dato({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline),
        ),
        Text(valor, style: t.textTheme.titleMedium),
      ],
    );
  }
}
