import 'dart:async';

import 'package:flutter/material.dart';

import '../features/combustible/registro_cargas.dart';
import '../features/odometro/fuente.dart';
import '../features/odometro/registro.dart';
import '../core/db/base.dart';
import '../core/registro_eventos.dart';
import '../features/nube/cola.dart';
import '../features/nube/credencial.dart';
import '../features/nube/servicio_nube.dart';
import '../features/sensores/satelites.dart';
import '../features/odometro/pantalla_despierta.dart';
import '../features/odometro/cascada.dart';
import '../features/odometro/modo_recordado.dart';
import '../features/odometro/fuente_gps.dart';
import '../features/permisos/avisos.dart';
import '../features/odometro/servicio.dart';
import '../features/odometro/validacion_odometro.dart';
import '../features/vibracion/analisis.dart';
import '../features/vibracion/registro_vibracion.dart';
import '../features/vibracion/servicio_vibracion.dart';
import 'formato.dart';
import 'pantalla_combustible.dart';
import 'pantalla_diagnostico.dart';
import 'pantalla_respaldo.dart';
import 'pantalla_sensores.dart';
import 'pantalla_vibracion.dart';

/// La pantalla del viaje en curso.
///
/// Está pensada para mirarse de reojo desde el asiento: los kilómetros en
/// grande y todo lo demás chico. Lo que se toca —empezar, pausar, terminar—
/// son botones de 56 px, que es lo que se acierta con la camioneta en
/// movimiento y sin mirar.
class PantallaViaje extends StatefulWidget {
  final ServicioOdometria servicio;
  final RegistroDeViajes registro;
  final RegistroDeCargas cargas;
  final RegistroDeVibracion vibraciones;
  final ServicioVibracion vibracion;
  final PantallaDespierta despierta;

  /// La cascada de modos del GPS. Es opcional porque el banco arma la pantalla
  /// con una fuente de mentira, que no tiene modos que mostrar.
  final FuenteEnCascada? gps;

  /// La bitácora en disco y la escucha del motor GNSS, para el reporte.
  final RegistroDeEventos? eventos;
  final Satelites? satelites;

  /// El modo de GPS que entregó la última vez.
  final ModoRecordado? modoRecordado;

  /// La subida automática: la cola, el que sube y dónde vive la configuración.
  final ColaDeSubida? cola;
  final ServicioNube? nube;
  final GuardaDeCredencial? guarda;

  final Base base;
  final String ruta;

  const PantallaViaje({
    super.key,
    required this.servicio,
    required this.registro,
    required this.cargas,
    required this.vibraciones,
    required this.vibracion,
    required this.despierta,
    this.gps,
    this.eventos,
    this.satelites,
    this.modoRecordado,
    this.cola,
    this.nube,
    this.guarda,
    required this.base,
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
    // Si el viaje ya estaba abierto (venía en pausa, o lo retomó la
    // aplicación después de que el sistema la matara), no se vuelve a
    // preguntar el odómetro: el tramo ya empezó.
    double? odometro;
    if (!widget.servicio.estado.value.hayViaje) {
      final pedido = await _pedirOdometro(
        titulo: 'Empezar el viaje',
        explicacion:
            'Si vas a hacer más de 20 km, anotá lo que marca el odómetro del '
            'tablero. Con esa lectura y la de la llegada, la aplicación '
            'aprende sola cuánto miente el tablero con los neumáticos que '
            'tenés puestos. Para un viaje corto no sirve de nada: el '
            'odómetro avanza de a 1 km.',
        aceptar: 'Empezar',
      );
      if (pedido == null) return; // se arrepintió
      odometro = pedido.valor;
    }
    final ok = await widget.servicio.arrancar(odoTablero: odometro);
    if (!ok) {
      if (mounted) {
        final problema = widget.servicio.estado.value.problema;
        if (problema != null) _avisar(problema);
      }
      return;
    }
    // El acelerómetro va pegado al viaje: sin viaje no hay a qué colgarle una
    // ventana, y sin velocidad no hay cubeta con la cual compararla.
    final viaje = widget.servicio.estado.value.viaje;
    if (viaje != null) widget.vibracion.arrancar(viaje);
    await widget.despierta.segun(midiendo: true);
  }

  Future<void> _pausar() async {
    await widget.vibracion.detener();
    await widget.servicio.pausar();
    await widget.despierta.segun(midiendo: false);
  }

  /// Pide una lectura del odómetro sin obligar a darla: devuelve `null` si se
  /// canceló, y un [_Odometro] con `valor` en nulo si se siguió sin anotar.
  Future<_Odometro?> _pedirOdometro({
    required String titulo,
    required String explicacion,
    required String aceptar,
    String? extra,
  }) async {
    final campo = TextEditingController();
    final valor = await showDialog<_Odometro>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (extra != null) ...[Text(extra), const SizedBox(height: 12)],
            Text(explicacion, style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: campo,
              autofocus: false,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Odómetro del tablero (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              _Odometro(
                double.tryParse(campo.text.trim().replaceAll(',', '.')),
              ),
            ),
            child: Text(aceptar),
          ),
        ],
      ),
    );
    campo.dispose();
    return valor;
  }

  /// El cartel del odómetro imposible. **Ofrece el número que sí cierra**, que
  /// es lo que convierte un aviso en una solución: sacando un dígito, `4055086`
  /// da `405086`. Los otros dos caminos son volver a escribirlo y dejarlo sin
  /// anotar — ninguno de los tres pierde el viaje.
  Future<_Odometro?> _confirmarOdometro(RevisionOdometro r) async {
    final sug = r.sugerido;
    return showDialog<_Odometro>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Ese odómetro no cierra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.mensaje),
            const SizedBox(height: 12),
            Text(
              'El viaje NO se pierde: elegí una y seguimos.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, const _Odometro(null)),
            child: const Text('Terminar sin anotarlo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Volver a escribirlo'),
          ),
          if (sug != null)
            FilledButton(
              onPressed: () => Navigator.pop(c, _Odometro(sug)),
              child: Text('Usar ${sug.toStringAsFixed(0)}'),
            ),
        ],
      ),
    );
  }

  void _ir(Widget pantalla) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => pantalla));

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
    // Una confirmación dice qué pasa exactamente, no «¿estás seguro?».
    final pedido = await _pedirOdometro(
      titulo: 'Terminar el viaje',
      extra:
          'Se cierra el viaje con ${formatearKm(viaje.kilometros)} y queda '
          'guardado. Las muestras del GPS no se borran: el viaje se puede '
          'volver a calcular cuando mejore el filtro.',
      explicacion:
          'Si anotaste el odómetro al salir, anotá también el de llegada: ese '
          'par es lo que calibra el factor de neumáticos.',
      aceptar: 'Terminar',
    );
    if (pedido == null) return;

    /* ── EL ODÓMETRO SE REVISA ANTES DE GUARDARLO (`sitd-22`) ──────────────
       El viaje del 2026-09-20 se cerró con `4055086` en vez de `405086` —un
       cinco de más— y el dato quedó guardado, se subió a la nube y se
       descubrió tres días después leyendo el respaldo con los ojos. Lo que
       faltaba no era un límite, era comparar contra lo que el GPS acababa de
       medir del MISMO viaje. */
    var odo = pedido.valor;
    // La lectura de salida no está en el estado vivo —ahí va lo que cambia
    // cada segundo— sino en el registro, que es donde se guardó al arrancar.
    final abierto = widget.registro.abierto;
    final revision = revisarOdometro(
      odoInicial: abierto?.odoTableroIni,
      odoFinal: odo,
      kmGps: viaje.kilometros,
    );
    if (!revision.entra) {
      if (!mounted) return;
      final corregido = await _confirmarOdometro(revision);
      // Cerró el cartel sin elegir: no se termina el viaje, que sigue abierto
      // y se puede volver a intentar. Perder el viaje por un dedo sería peor.
      if (corregido == null) return;
      odo = corregido.valor;
    } else if (revision.veredicto == Veredicto.sospechoso && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(revision.mensaje),
          duration: const Duration(seconds: 8),
        ),
      );
    }

    await widget.vibracion.detener();
    await widget.servicio.terminar(odoTablero: odo);
    await widget.despierta.segun(midiendo: false);
    if (mounted) await _avisarDeLaVibracion();
  }

  /// El aviso de vibración sale al TERMINAR el viaje y en ningún otro momento.
  ///
  /// No es una preferencia de diseño: un cartel que aparece manejando es una
  /// distracción arriba de una camioneta de dos toneladas, y lo que se va a
  /// avisar viene repitiéndose hace tres viajes — puede esperar cinco minutos.
  Future<void> _avisarDeLaVibracion() async {
    final porViaje = widget.vibraciones.porViaje();
    final avisos = anomalias(porViaje, widget.vibraciones.ultimosViajes());
    if (avisos.isEmpty || !mounted) return;
    final a = avisos.first;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Algo vibra distinto'),
        content: Text(textoDeAnomalia(a)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Entendido'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PantallaVibracion(registro: widget.vibraciones),
                ),
              );
            },
            child: const Text('Ver el detalle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SITD Hilux'),
        actions: [
          IconButton(
            tooltip: 'Combustible',
            icon: const Icon(Icons.local_gas_station),
            onPressed: () => _ir(
              PantallaCombustible(
                cargas: widget.cargas,
                viajes: widget.registro,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Vibración',
            icon: const Icon(Icons.graphic_eq),
            onPressed: () =>
                _ir(PantallaVibracion(registro: widget.vibraciones)),
          ),
          // Las dos pantallas de diagnóstico van juntas y detrás de un menú:
          // cuatro iconos en la barra de un teléfono dejan de leerse, y éstas
          // se abren cuando algo anda raro, no todos los días.
          PopupMenuButton<String>(
            tooltip: 'Diagnóstico',
            onSelected: (que) => _ir(switch (que) {
              'sensores' => PantallaSensores(
                servicio: widget.servicio,
                satelites: widget.satelites,
                modoRecordado: widget.modoRecordado,
                // Para poder abrir «Probar la medición», que guarda sus
                // pruebas en la base.
                base: widget.base,
              ),
              'respaldo' => PantallaRespaldo(
                base: widget.base,
                viajes: widget.registro,
                cargas: widget.cargas,
                vibraciones: widget.vibraciones,
                ruta: widget.ruta,
                eventos: widget.eventos,
                satelites: widget.satelites,
                cola: widget.cola,
                nube: widget.nube,
                guarda: widget.guarda,
              ),
              _ => PantallaDiagnostico(
                registro: widget.registro,
                ruta: widget.ruta,
              ),
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'sensores',
                child: ListTile(
                  leading: Icon(Icons.sensors),
                  title: Text('Sensores'),
                  subtitle: Text('Qué ve el teléfono ahora mismo'),
                ),
              ),
              PopupMenuItem(
                value: 'respaldo',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Sacar los datos'),
                  subtitle: Text('Reporte para arreglar, o respaldo'),
                ),
              ),
              PopupMenuItem(
                value: 'estado',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Estado'),
                  subtitle: Text('Versión, base y últimos viajes'),
                ),
              ),
            ],
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
              if (widget.gps != null && e.midiendo) ...[
                _Cascada(gps: widget.gps!),
                const SizedBox(height: 12),
              ],
              _Detalle(estado: e, vibracion: widget.vibracion),
              const SizedBox(height: 12),
              _Despierta(
                despierta: widget.despierta,
                midiendo: e.midiendo,
                alCambiar: () => setState(() {}),
              ),
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
                          onPressed: _pausar,
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
  final ServicioVibracion vibracion;

  const _Detalle({required this.estado, required this.vibracion});

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
            // Sirve para saber, sin salir de acá, si el acelerómetro está
            // juntando algo: a velocidad de ciudad no junta nada a propósito,
            // y eso de afuera se ve igual que un sensor que no anda.
            _Dato(titulo: 'Vibración', valor: '${vibracion.guardadas}'),
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

/// Lo que devuelve el diálogo del odómetro. Una clase de un campo y no un
/// `double?` suelto, porque hay que distinguir tres cosas: canceló (nulo),
/// siguió sin anotar (`valor` nulo) y anotó un número.
class _Odometro {
  final double? valor;

  const _Odometro(this.valor);
}

/// El interruptor de la pantalla encendida.
///
/// Está en la pantalla del viaje y no escondido en ajustes porque la decisión
/// se toma justo antes de salir —con la camioneta enchufada o no, al sol o a
/// la sombra— y no una vez en la vida.
class _Despierta extends StatelessWidget {
  final PantallaDespierta despierta;
  final bool midiendo;
  final VoidCallback alCambiar;

  const _Despierta({
    required this.despierta,
    required this.midiendo,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: SwitchListTile(
        value: despierta.preferida,
        onChanged: (v) async {
          despierta.preferida = v;
          await despierta.segun(midiendo: midiendo);
          alCambiar();
        },
        title: const Text('Pantalla encendida mientras mide'),
        subtitle: Text(
          despierta.preferida
              ? 'No se apaga sola durante el viaje. Con el teléfono al sol y '
                    'enchufado, eso es calor que se suma: apagalo si la '
                    'cabina se pone brava.'
              : 'Se apaga sola, como cualquier pantalla. Se sigue midiendo '
                    'igual, pero hay que desbloquear para mirar los '
                    'kilómetros.',
          style: t.textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// En qué escalón de la cascada está el GPS, y cómo quedó el permiso de la
/// notificación.
///
/// **No es un adorno: es el dato que hoy falta.** Si un viaje termina midiendo
/// y el modo que quedó puesto no es «Normal», eso dice exactamente dónde está
/// el problema —el servicio en primer plano, o Play Services— sin tener que
/// volver a salir a probarlo. Y si dice «Normal», la cascada nunca hizo falta.
class _Cascada extends StatelessWidget {
  final FuenteEnCascada gps;

  const _Cascada({required this.gps});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ValueListenableBuilder<ModoGps>(
      valueListenable: gps.modo,
      builder: (context, modo, _) => ValueListenableBuilder<EstadoAviso?>(
        valueListenable: gps.aviso,
        builder: (context, aviso, _) {
          final normal = modo == ModoGps.normal;
          final sinCartel = aviso != null && aviso != EstadoAviso.concedido;
          return Card(
            // **No va en rojo, y es a propósito.** Mauro lo vio el 2026-09-19:
            // un cartel de error mientras el viaje medía perfecto —105
            // muestras, ninguna descartada—. El rojo es para lo que IMPIDE
            // medir; esto es una advertencia sobre una capacidad que se
            // perdió, no una falla. Un rojo que aparece cuando todo anda
            // enseña a no mirar los rojos.
            color: normal && !sinCartel
                ? t.colorScheme.surfaceContainerHighest
                : t.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GPS pedido en modo ${nombreDeModo(modo)}',
                    style: t.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    normal
                        ? 'Es el modo bueno: servicio en primer plano, sigue '
                              'midiendo con la pantalla apagada.'
                        : 'Está midiendo bien. Lo que se pierde es concreto: '
                              'sin servicio en primer plano, el GPS se '
                              'apaga si se apaga la pantalla, y el sistema '
                              'puede matar la aplicación. Dejá la pantalla '
                              'encendida mientras dure el viaje.',
                    style: t.textTheme.bodySmall,
                  ),
                  if (sinCartel) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Permiso de notificaciones: ${textoDeAviso(aviso)}. Sin '
                      'él el servicio queda sin cartel, y un servicio en '
                      'primer plano invisible es lo que HyperOS mata sin '
                      'avisar. Se da en Ajustes → Aplicaciones → SITD Hilux → '
                      'Notificaciones.',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
