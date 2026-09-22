import 'dart:async';

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
/// ## Las dos cosas que tiene que dejar hacer
///
/// **Probar un modo** — pedir 200, 66, 20 ms o «lo más rápido», y ver qué
/// entrega el teléfono de verdad. De ahí sale el número que decide si el
/// tacómetro es posible sin micrófono.
///
/// **Comparar dos soportes** — y eso no se puede de memoria. Uno mira la
/// pantalla, se baja, ata el teléfono en otro lado, vuelve a mirar, y ya no se
/// acuerda del primero. Por eso cada medición se puede GUARDAR con el nombre
/// del soporte y de la situación, y la lista queda ordenada por nitidez.
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

class _PantallaCalidadState extends State<PantallaCalidad> {
  StreamSubscription<Sacudon>? _suscripcion;
  Timer? _reloj;
  final List<Sacudon> _buffer = [];
  Calidad? _calidad;

  /// El período pedido, en milisegundos. Arranca en el que usa el viaje: si
  /// alguien abre esto sin tocar nada, lo que ve es lo que está midiendo de
  /// verdad, no una configuración de prueba.
  int _periodoMs = 20;

  @override
  void initState() {
    super.initState();
    _escuchar();
    /* Dos veces por segundo y no en cada muestra. A 400 Hz un `setState` por
       lectura son cuatrocientas reconstrucciones del árbol por segundo en un
       Helio G85: es la misma regla que la pantalla de sensores. */
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _calidad = medirCalidad(List.of(_buffer)));
    });
  }

  void _escuchar() {
    _suscripcion?.cancel();
    _buffer.clear();
    _calidad = null;
    final fuente = Acelerometro(periodo: Duration(milliseconds: _periodoMs));
    _suscripcion = fuente.sacudones.listen((s) {
      _buffer.add(s);
      if (_buffer.length > muestrasEnVuelo) _buffer.removeAt(0);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _suscripcion?.cancel();
    super.dispose();
  }

  Future<void> _guardar() async {
    final c = _calidad;
    if (c == null || !c.sirve) return;
    final registro = RegistroDePruebas(widget.base);
    final soporte = TextEditingController();
    final situacion = TextEditingController();
    final notas = TextEditingController();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar esta prueba'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dos pruebas sólo se pueden comparar si midieron lo mismo. La '
                'situación es lo que hace que la comparación valga: un soporte '
                'que parece mejor puede ser el que se probó con el motor en '
                'marcha.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: soporte,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Dónde está el teléfono',
                  hintText: 'tablero / palanca de cambios / piso',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: situacion,
                decoration: const InputDecoration(
                  labelText: 'Qué estaba pasando',
                  hintText: 'motor apagado / ralentí / andando a 80',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notas,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
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
    );

    if (guardar == true && soporte.text.trim().isNotEmpty) {
      registro.guardar(
        PruebaDeSensor(
          t: DateTime.now().millisecondsSinceEpoch,
          soporte: soporte.text.trim(),
          periodoMs: _periodoMs,
          situacion: situacion.text.trim().isEmpty
              ? null
              : situacion.text.trim(),
          notas: notas.text.trim().isEmpty ? null : notas.text.trim(),
          calidad: c,
        ),
      );
      if (mounted) setState(() {});
    }
    soporte.dispose();
    situacion.dispose();
    notas.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = _calidad;
    final guardadas = RegistroDePruebas(widget.base).ultimas(20);

    return Scaffold(
      appBar: AppBar(title: const Text('Probar la medición')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Esto mide el SENSOR, no la camioneta. Sirve para dos cosas: ver '
            'qué entrega el teléfono con cada modo, y comparar soportes — el '
            'tablero contra la palanca de cambios, por ejemplo.',
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

          if (c == null || !c.sirve)
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
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Guardar esta prueba'),
              ),
            ),
          ],

          if (guardadas.isNotEmpty) ...[
            const SizedBox(height: 24),
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
            for (final p in guardadas)
              Card(
                child: ListTile(
                  title: Text(
                    '${p.soporte}'
                    '${p.situacion == null ? '' : ' · ${p.situacion}'}',
                  ),
                  subtitle: Text(
                    '${formatearFechaYHora(p.t)} · pedido ${p.comoSePidio}\n'
                    '${p.calidad.hz.toStringAsFixed(1)} Hz medidos · '
                    'nitidez ${p.calidad.nitidez.toStringAsFixed(1)}× · '
                    'irregularidad '
                    '${p.calidad.irregularidad.toStringAsFixed(2)}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      RegistroDePruebas(widget.base).borrar(p.id!);
                      setState(() {});
                    },
                  ),
                ),
              ),
          ],
        ],
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
