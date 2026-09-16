import 'package:flutter/material.dart';

import '../features/combustible/carga.dart';
import '../features/combustible/consumo.dart';
import '../features/combustible/registro_cargas.dart';
import '../features/odometro/factor.dart';
import '../features/odometro/registro.dart';
import 'formato.dart';
import 'pantalla_carga.dart';

/// Combustible: las cargas, el consumo que sale de ellas y el factor de
/// neumáticos que se fue aprendiendo.
///
/// Todo lo que se muestra acá es **derivado y se calcula al leer**. En la base
/// sólo están las cargas tal como se tecleaon en la estación.
class PantallaCombustible extends StatefulWidget {
  final RegistroDeCargas cargas;
  final RegistroDeViajes viajes;

  const PantallaCombustible({
    super.key,
    required this.cargas,
    required this.viajes,
  });

  @override
  State<PantallaCombustible> createState() => _PantallaCombustibleState();
}

class _PantallaCombustibleState extends State<PantallaCombustible> {
  Future<void> _cargar() async {
    final carga = await Navigator.of(context).push<Carga>(
      MaterialPageRoute(
        builder: (_) =>
            PantallaCarga(odometroPrevio: widget.cargas.ultimoOdometro),
      ),
    );
    if (carga == null) return;
    widget.cargas.guardar(carga);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cargas = widget.cargas.todas();
    final factor = factorRobusto(widget.viajes.paresDeCalibracion());
    final consumo = calcularConsumo(cargas, k: factor?.k ?? 1.0);
    final tanque = widget.cargas.litrosDelTanque;

    return Scaffold(
      appBar: AppBar(title: const Text('Combustible')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _Consumo(consumo: consumo, tanque: tanque),
          const SizedBox(height: 12),
          _Factor(factor: factor),
          const SizedBox(height: 16),
          Text('Cargas', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (cargas.isEmpty)
            Text(
              'Todavía no hay ninguna. La primera no va a dar consumo —hace '
              'falta un tramo entre dos tanques llenos para eso— pero es la '
              'que lo empieza a contar.',
              style: t.textTheme.bodySmall,
            ),
          for (final c in cargas.reversed) _FilaCarga(carga: c),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _cargar,
            icon: const Icon(Icons.local_gas_station),
            label: const Text('Cargar combustible'),
          ),
        ),
      ),
    );
  }
}

class _Consumo extends StatelessWidget {
  final Consumo consumo;
  final double tanque;

  const _Consumo({required this.consumo, required this.tanque});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final promedio = consumo.litrosCada100;
    final ultima = consumo.ultima;
    final autonomia = consumo.autonomia(tanque);

    if (promedio == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Consumo', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                // Un cero acá sería mentira: no es que consuma cero, es que
                // todavía no se puede saber.
                'Todavía no se puede calcular. Hace falta llenar el tanque, '
                'andar, y volver a llenarlo: entre esos dos llenados los '
                'litros que entran son exactamente los que se quemaron.',
                style: t.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatearConsumo(promedio), style: t.textTheme.displaySmall),
            Text(
              'promedio de ${consumo.ventanas.length} '
              '${consumo.ventanas.length == 1 ? "tramo" : "tramos"} · '
              '${formatearKm(consumo.kmTotales)}',
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                if (ultima != null)
                  _Dato(
                    titulo: 'Último tramo',
                    valor: formatearConsumo(ultima.litrosCada100),
                  ),
                if (autonomia != null)
                  _Dato(
                    titulo: 'Tanque lleno ($tanque L)',
                    valor: formatearKm(autonomia),
                  ),
                for (final moneda in const ['UYU', 'USD'])
                  if (consumo.costoPorKm(moneda) != null)
                    _Dato(
                      titulo: 'Costo por km',
                      valor: formatearDinero(
                        consumo.costoPorKm(moneda)!,
                        moneda,
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Factor extends StatelessWidget {
  final Factor? factor;

  const _Factor({required this.factor});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = factor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Factor de neumáticos', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (f == null)
              Text(
                'Todavía no se aprendió. Sale de comparar el GPS con el '
                'odómetro del tablero en tramos de 20 km o más: anotá lo que '
                'marca el tablero al empezar y al terminar un viaje largo y '
                'se calcula solo. Mientras tanto, los kilómetros del tablero '
                'se usan tal cual.',
                style: t.textTheme.bodySmall,
              )
            else ...[
              Text(
                'k = ${f.k.toStringAsFixed(4).replaceAll('.', ',')}',
                style: t.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'El tablero marca '
                '${f.errorPorcentual.abs().toStringAsFixed(1).replaceAll('.', ',')} % '
                '${f.errorPorcentual >= 0 ? "de MENOS" : "de MÁS"} que la '
                'distancia real, aprendido de ${f.pares} '
                '${f.pares == 1 ? "tramo" : "tramos"}.',
                style: t.textTheme.bodySmall,
              ),
              if (f.dispersion > 0.03) ...[
                const SizedBox(height: 8),
                Text(
                  'Los tramos no se parecen entre sí '
                  '(${(f.dispersion * 100).toStringAsFixed(1)} % de '
                  'dispersión). Suele ser un odómetro mal anotado: el factor '
                  'todavía no es de fiar.',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaCarga extends StatelessWidget {
  final Carga carga;

  const _FilaCarga({required this.carga});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final precio = carga.precioPorLitro;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        carga.tanqueLleno ? Icons.local_gas_station : Icons.opacity,
        color: carga.tanqueLleno ? t.colorScheme.primary : null,
      ),
      title: Text(
        '${formatearLitros(carga.litros)}'
        '${carga.costo == null ? "" : " · ${formatearDinero(carga.costo!, carga.moneda)}"}',
      ),
      subtitle: Text(
        '${formatearFecha(carga.t)} · '
        '${carga.odoTablero.toStringAsFixed(0)} km'
        '${carga.tanqueLleno ? "" : " · parcial"}'
        '${precio == null ? "" : " · ${formatearDinero(precio, carga.moneda)}/L"}'
        '${carga.estacion == null ? "" : " · ${carga.estacion}"}',
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
