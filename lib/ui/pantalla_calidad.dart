import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../core/db/base.dart';
import '../features/vibracion/calidad.dart';
import '../features/vibracion/fuente_vibracion.dart';
import '../features/vibracion/registro_pruebas.dart';
import 'formato.dart';

/// Medir la MEDICIÓN, sentado en la camioneta.
///
/// ## Por qué existe
///
/// Lo pidió Mauro el 2026-09-22: «no estoy muy seguro de lo confiable de los
/// modos de medición… quizás fijando el teléfono a un punto más fijo, atado a
/// la palanca de cambios». Las dos mitades de esa duda —el modo y el soporte—
/// no se discuten: se miden.
///
/// Es la misma idea que el panel de sensores, que entró después de un viaje de
/// siete minutos que dio cero sin que se pudiera saber por qué. Acá el
/// problema sería peor, porque un soporte malo **sí da números**: da un
/// espectro con forma de espectro, del que no se puede deducir nada y que no
/// avisa.
///
/// ## Las tres cosas que tiene que dejar hacer
///
/// **Probar un modo** — pedir 200, 66, 20 ms o «lo más rápido», y ver qué
/// entrega el teléfono de verdad. De ahí sale el número que decide si el
/// tacómetro es posible sin micrófono.
///
/// **Anotar lo que se ve, mientras se ve.** El cuadro de observaciones está a
/// la vista y no adentro del diálogo de guardar, y eso lo pidió Mauro el mismo
/// día: el que mide está mirando números que se mueven, y lo que quiere
/// escribir —«acá pasé un pozo», «a 2000 el pico salta a 16 Hz»— se le ocurre
/// en ese momento, no cuando toca Guardar. Además hay un botón que **sella la
/// lectura de ahora mismo** adentro del texto: una observación sin los números
/// al lado no se puede releer.
///
/// **Comparar dos soportes** — y eso no se puede de memoria. Uno mira la
/// pantalla, se baja, ata el teléfono en otro lado, vuelve a mirar, y ya no se
/// acuerda del primero. Por eso cada medición se GUARDA con el soporte, la
/// situación y la observación, y la lista queda ordenada por nitidez.
class PantallaCalidad extends StatefulWidget {
  final Base base;

  const PantallaCalidad({super.key, required this.base});

  @override
  State<PantallaCalidad> createState() => _PantallaCalidadState();
}

/// Los períodos que se pueden pedir, con el nombre que tienen en Android.
///
/// Se ofrecen los cuatro y no sólo el que usa el viaje, porque el punto de
/// esta pantalla es justamente comparar: lo que Android entrega con cada uno
/// no está escrito en ningún lado y depende del aparato.
const List<({String nombre, int ms})> periodosPosibles = [
  (nombre: 'Normal · 5 Hz', ms: 200),
  (nombre: 'Interfaz · 15 Hz', ms: 66),
  (nombre: 'Juego · 50 Hz', ms: 20),
  (nombre: 'Lo más rápido', ms: 0),
];

/// Cuántas muestras se guardan para medir. A 400 Hz son cinco segundos.
const int muestrasEnVuelo = 2048;

/// Dónde vive el borrador de la observación mientras no se guardó.
///
/// En `ajustes` y no en memoria: un teléfono atornillado a una cabina lo mata
/// MIUI sin avisar, y perder lo que alguien acaba de escribir con el motor en
/// marcha es exactamente la clase de pérdida que este proyecto ya decidió no
/// aceptar en ningún lado.
const String claveDelBorrador = 'observacion_borrador';

class _PantallaCalidadState extends State<PantallaCalidad> {
  StreamSubscription<Sacudon>? _suscripcion;
  Timer? _reloj;

  /// Una cola y no una lista: sacar el primero de una `List` mueve los otros
  /// dos mil, y a 400 Hz eso es casi un millón de corrimientos por segundo en
  /// un Helio G85. `ListQueue.removeFirst` es constante.
  final ListQueue<Sacudon> _buffer = ListQueue();

  Calidad? _calidad;
  final _observacion = TextEditingController();
  String _guardadoUltimo = '';
  int _tics = 0;

  /// La lista de pruebas se lee de la base, y la pantalla se redibuja dos
  /// veces por segundo: leerla en cada `build` serían dos consultas por
  /// segundo para siempre. Se guarda acá y se refresca sólo cuando cambia.
  List<PruebaDeSensor> _guardadas = const [];

  /// El período pedido, en milisegundos. Arranca en el que usa el viaje: si
  /// alguien abre esto sin tocar nada, lo que ve es lo que está midiendo de
  /// verdad, no una configuración de prueba.
  int _periodoMs = 20;

  @override
  void initState() {
    super.initState();
    _observacion.text = widget.base.leerAjuste(claveDelBorrador) ?? '';
    _guardadoUltimo = _observacion.text;
    _guardadas = RegistroDePruebas(widget.base).ultimas(20);
    _escuchar();
    /* Dos veces por segundo y no en cada muestra. A 400 Hz un `setState` por
       lectura son cuatrocientas reconstrucciones del árbol por segundo: es la
       misma regla que la pantalla de sensores. */
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _calidad = medirCalidad(_buffer.toList()));
      // Y el borrador a disco cada cinco segundos, no en cada tecla.
      if (++_tics % 10 == 0) _guardarBorrador();
    });
  }

  void _guardarBorrador() {
    if (_observacion.text == _guardadoUltimo) return;
    widget.base.escribirAjuste(claveDelBorrador, _observacion.text);
    _guardadoUltimo = _observacion.text;
  }

  void _escuchar() {
    _suscripcion?.cancel();
    _buffer.clear();
    _calidad = null;
    final fuente = Acelerometro(periodo: Duration(milliseconds: _periodoMs));
    _suscripcion = fuente.sacudones.listen((s) {
      _buffer.addLast(s);
      if (_buffer.length > muestrasEnVuelo) _buffer.removeFirst();
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _suscripcion?.cancel();
    _guardarBorrador();
    _observacion.dispose();
    super.dispose();
  }

  /// Mete la lectura de este instante adentro del texto.
  ///
  /// **Es la mitad del valor del cuadro.** Una observación que dice «acá saltó»
  /// no se puede releer tres días después: hace falta saber qué decía el
  /// instrumento en ese momento, y nadie va a copiar nueve números a mano con
  /// el motor en marcha.
  void _sellarLectura() {
    final c = _calidad;
    if (c == null || !c.sirve) return;
    final t = DateTime.now().millisecondsSinceEpoch;
    final linea =
        '${formatearHora(t)} · ${c.hz.toStringAsFixed(1)} Hz · '
        'pico ${c.picoHz.toStringAsFixed(1)} Hz · '
        'nitidez ${c.nitidez.toStringAsFixed(1)}× · '
        'irreg ${c.irregularidad.toStringAsFixed(2)}';
    final actual = _observacion.text;
    setState(() {
      _observacion.text = actual.isEmpty ? '$linea — ' : '$actual\n$linea — ';
      _observacion.selection = TextSelection.collapsed(
        offset: _observacion.text.length,
      );
    });
    _guardarBorrador();
  }

  Future<void> _guardar() async {
    final c = _calidad;
    if (c == null || !c.sirve) return;
    final soporte = TextEditingController();
    final situacion = TextEditingController();
    final anteriores = RegistroDePruebas(widget.base).situaciones();

    final listo = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refrescar) => AlertDialog(
          title: const Text('Guardar esta prueba'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dos pruebas sólo se pueden comparar si midieron lo mismo. '
                  'La situación es lo que hace que la comparación valga: un '
                  'soporte que parece mejor puede ser el que se probó con el '
                  'motor en marcha.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: soporte,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Dónde está el teléfono',
                    hintText: 'tablero / soporte / piso',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: situacion,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Qué estaba pasando',
                    hintText: 'motor apagado / ralentí / andando a 80',
                    border: OutlineInputBorder(),
                  ),
                ),
                // Las situaciones que ya se usaron, para tocar en vez de
                // teclear: si se escriben distinto, las pruebas dejan de
                // compararse entre sí sin que nada avise.
                if (anteriores.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final s in anteriores.take(5))
                        ActionChip(
                          label: Text(s),
                          onPressed: () => refrescar(() {
                            situacion.text = s;
                          }),
                        ),
                    ],
                  ),
                ],
                if (_observacion.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Se guarda con la observación que escribiste:',
                    style: Theme.of(ctx).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _observacion.text.trim(),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (listo == true && soporte.text.trim().isNotEmpty) {
      final registro = RegistroDePruebas(widget.base);
      registro.guardar(
        PruebaDeSensor(
          t: DateTime.now().millisecondsSinceEpoch,
          soporte: soporte.text.trim(),
          periodoMs: _periodoMs,
          situacion: situacion.text.trim().isEmpty
              ? null
              : situacion.text.trim(),
          notas: _observacion.text.trim().isEmpty
              ? null
              : _observacion.text.trim(),
          calidad: c,
        ),
      );
      if (mounted) {
        setState(() {
          /* Se limpia porque la observación YA está guardada y se ve en la
             lista de abajo: dejarla escrita haría dudar de si se guardó, y
             además se le pegaría a la próxima prueba sin que nadie lo pida. */
          _observacion.clear();
          _guardadas = registro.ultimas(20);
        });
        _guardarBorrador();
      }
    }
    soporte.dispose();
    situacion.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = _calidad;
    final hayLectura = c != null && c.sirve;

    return Scaffold(
      appBar: AppBar(title: const Text('Probar la medición')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Esto mide el SENSOR, no la camioneta. Sirve para dos cosas: ver '
            'qué entrega el teléfono con cada modo, y comparar soportes.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),

          Text('Qué período se le pide', style: t.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final p in periodosPosibles)
                ChoiceChip(
                  label: Text(p.nombre),
                  selected: _periodoMs == p.ms,
                  onSelected: (_) {
                    setState(() => _periodoMs = p.ms);
                    _escuchar();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'El período que se pide NO es el que se recibe: Android lo trata '
            'como una sugerencia y cada aparato entrega lo que puede. Eso es '
            'justamente lo que hay que averiguar.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 18),

          if (!hayLectura)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  c?.problema ??
                      'Midiendo… dejá el teléfono quieto en su soporte unos '
                          'segundos.',
                  style: t.textTheme.bodyMedium,
                ),
              ),
            )
          else ...[
            _Numeros(calidad: c),
            const SizedBox(height: 12),
            for (final h in leerCalidad(c)) _Renglon(hallazgo: h),
          ],

          // ── El cuadro de observaciones ──────────────────────────────────
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text('Observaciones', style: t.textTheme.titleMedium),
              ),
              if (_observacion.text.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(_observacion.clear);
                    _guardarBorrador();
                  },
                  child: const Text('Limpiar'),
                ),
            ],
          ),
          Text(
            'Lo que escribas acá se guarda con la prueba. No se pierde si '
            'salís de la pantalla ni si el sistema cierra la aplicación.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _observacion,
            maxLines: 6,
            minLines: 4,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText:
                  'Qué estás viendo, qué cambió, qué te llamó la atención.\n'
                  'Ej: acá pasé un pozo · a 2000 el pico salta a 16 Hz',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hayLectura ? _sellarLectura : null,
                  icon: const Icon(Icons.push_pin_outlined),
                  label: const Text('Anotar la lectura'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hayLectura ? _guardar : null,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Guardar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '«Anotar la lectura» mete los números de este instante adentro del '
            'texto, con la hora. Una observación sin los números al lado no se '
            'puede releer tres días después.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),

          // ── Lo guardado ────────────────────────────────────────────────
          if (_guardadas.isNotEmpty) ...[
            const SizedBox(height: 26),
            Text('Pruebas guardadas', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Para comparar dos soportes, mirá los que tengan la MISMA '
              'situación y compará la nitidez: es cuánto sobresale lo que se '
              'quiere ver por encima del ruido.',
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            for (final p in _guardadas) _Guardada(prueba: p, alBorrar: _borrar),
          ],
        ],
      ),
    );
  }

  void _borrar(PruebaDeSensor p) {
    final r = RegistroDePruebas(widget.base);
    r.borrar(p.id!);
    setState(() => _guardadas = r.ultimas(20));
  }
}

/// Una prueba guardada, con su observación a la vista.
///
/// La observación se muestra y no se esconde detrás de un toque: si hay que
/// abrir algo para leerla, en la práctica no se lee, y entonces no servía de
/// nada haberla escrito.
class _Guardada extends StatelessWidget {
  final PruebaDeSensor prueba;
  final void Function(PruebaDeSensor) alBorrar;

  const _Guardada({required this.prueba, required this.alBorrar});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = prueba.calidad;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prueba.soporte +
                        (prueba.situacion == null
                            ? ''
                            : ' · ${prueba.situacion}'),
                    style: t.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatearFechaYHora(prueba.t)} · '
                    'pedido ${prueba.comoSePidio}',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${c.hz.toStringAsFixed(1)} Hz medidos · '
                    'nitidez ${c.nitidez.toStringAsFixed(1)}× · '
                    'irregularidad ${c.irregularidad.toStringAsFixed(2)} · '
                    'motor hasta ${c.rpmMaximoVisible.round()} RPM',
                    style: t.textTheme.bodySmall,
                  ),
                  if (prueba.notas != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(prueba.notas!, style: t.textTheme.bodySmall),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => alBorrar(prueba),
            ),
          ],
        ),
      ),
    );
  }
}

/// Los números crudos, para el que quiere el dato y no la frase.
class _Numeros extends StatelessWidget {
  final Calidad calidad;

  const _Numeros({required this.calidad});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = calidad;
    final filas = <(String, String)>[
      ('Entrega', '${c.hz.toStringAsFixed(2)} Hz'),
      ('Techo del espectro', '${c.nyquist.toStringAsFixed(2)} Hz'),
      ('Intervalo', '${c.dtMedianaMs.toStringAsFixed(2)} ms'),
      ('Irregularidad', c.irregularidad.toStringAsFixed(2)),
      ('Muestras que faltaron', '${c.huecos} de ${c.muestras}'),
      ('Saturadas', '${c.saturadas}'),
      ('Energía (RMS)', c.rms.toStringAsFixed(3)),
      ('Pico dominante', '${c.picoHz.toStringAsFixed(2)} Hz'),
      ('Nitidez del pico', '${c.nitidez.toStringAsFixed(1)}×'),
      ('Motor visible hasta', '${c.rpmMaximoVisible.round()} RPM'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final f in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(f.$1, style: t.textTheme.bodyMedium)),
                    Text(
                      f.$2,
                      style: t.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un hallazgo, con su color.
///
/// **El rojo es para lo que impide medir, no para lo que no salió perfecto.**
/// Es la misma regla que el cartel del modo de GPS: un rojo que aparece cuando
/// todo anda enseña a no mirar los rojos.
class _Renglon extends StatelessWidget {
  final Hallazgo hallazgo;

  const _Renglon({required this.hallazgo});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (color, icono) = switch (hallazgo.grado) {
      Grado.bueno => (t.colorScheme.primary, Icons.check_circle_outline),
      Grado.regular => (t.colorScheme.tertiary, Icons.error_outline),
      Grado.malo => (t.colorScheme.error, Icons.cancel_outlined),
      Grado.dato => (t.colorScheme.outline, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(hallazgo.texto, style: t.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
