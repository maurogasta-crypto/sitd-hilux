import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/combustible/carga.dart';

/// El formulario de una carga de combustible.
///
/// Se llena parado al lado del surtidor, con una mano, y a veces de noche. Por
/// eso: teclado numérico donde va un número, el odómetro propuesto con la
/// última lectura conocida, y **nada obligatorio que no haga falta** — el
/// costo, la estación y las notas se pueden dejar vacíos y la carga sirve
/// igual para calcular consumo.
class PantallaCarga extends StatefulWidget {
  /// La última lectura del odómetro que se conoce, para proponerla.
  final double? odometroPrevio;

  const PantallaCarga({super.key, this.odometroPrevio});

  @override
  State<PantallaCarga> createState() => _PantallaCargaState();
}

class _PantallaCargaState extends State<PantallaCarga> {
  final _litros = TextEditingController();
  final _costo = TextEditingController();
  final _odometro = TextEditingController();
  final _estacion = TextEditingController();
  final _notas = TextEditingController();

  String _moneda = 'UYU';
  // sitd-51: sin valor de entrada. Venía prendido y dos cargas parciales
  // quedaron como llenas sin que nadie lo eligiera.
  bool? _lleno;
  String? _problema;

  @override
  void dispose() {
    _litros.dispose();
    _costo.dispose();
    _odometro.dispose();
    _estacion.dispose();
    _notas.dispose();
    super.dispose();
  }

  /// La coma es lo que tiene el teclado en español y lo que se escribe acá.
  static double? _numero(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));

  void _guardar() {
    final litros = _numero(_litros.text);
    final odometro = _numero(_odometro.text);
    final carga = Carga(
      t: DateTime.now().millisecondsSinceEpoch,
      litros: litros ?? 0,
      costo: _costo.text.trim().isEmpty ? null : _numero(_costo.text),
      moneda: _moneda,
      odoTablero: odometro ?? 0,
      tanqueLleno: _lleno ?? true,
      estacion: _estacion.text.trim().isEmpty ? null : _estacion.text.trim(),
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
    );

    var problema = carga.problema;
    if (problema == null && _lleno == null) {
      problema = 'Elegí si cargaste hasta el corte o fue una carga parcial.';
    }
    // El odómetro no retrocede. Si retrocedió, casi siempre es que se
    // tecleó el cuentakilómetros parcial en vez del total.
    final previo = widget.odometroPrevio;
    if (problema == null && previo != null && carga.odoTablero < previo) {
      problema =
          'El odómetro marca menos que en la carga anterior '
          '(${previo.toStringAsFixed(0)} km). ¿Anotaste el parcial en vez del '
          'total?';
    }
    if (problema != null) {
      setState(() => _problema = problema);
      return;
    }
    Navigator.pop(context, carga);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final previo = widget.odometroPrevio;
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar combustible')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          if (_problema != null) ...[
            Card(
              color: t.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _problema!,
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: t.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _litros,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Litros',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _odometro,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Odómetro del tablero (km)',
              helperText: previo == null
                  ? 'El total, no el parcial'
                  : 'La vez pasada marcaba ${previo.toStringAsFixed(0)} km',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _costo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Costo (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Las dos monedas son dos sistemas y no se suman nunca, así que
              // elegirla no es un detalle: es a qué cuenta va esta carga.
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'UYU', label: Text('UYU')),
                  ButtonSegment(value: 'USD', label: Text('USD')),
                ],
                selected: {_moneda},
                onSelectionChanged: (s) => setState(() => _moneda = s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('¿Hasta dónde cargaste?'),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Hasta el corte'),
                icon: Icon(Icons.local_gas_station),
              ),
              ButtonSegment(
                value: false,
                label: Text('Parcial'),
                icon: Icon(Icons.opacity),
              ),
            ],
            selected: {?_lleno},
            onSelectionChanged: (s) =>
                setState(() => _lleno = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 4),
          Text(
            'El consumo se calcula de un llenado hasta el corte al siguiente. '
            'Una parcial no cierra el tramo, pero sus litros cuentan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _estacion,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Estación (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notas,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _guardar,
            icon: const Icon(Icons.check),
            label: const Text('Guardar la carga'),
          ),
        ),
      ),
    );
  }
}
