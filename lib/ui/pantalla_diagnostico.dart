import 'package:flutter/material.dart';

import '../core/bitacora.dart';
import '../core/version.dart';
import '../features/odometro/registro.dart';
import 'formato.dart';

/// La pantalla que contesta «¿esto anda?», que era toda la aplicación en la
/// tanda 1 y ahora vive detrás del icono de información.
///
/// Sigue sirviendo para lo mismo: en un teléfono atornillado a una cabina no
/// hay consola ni depurador, y la única forma de saber qué APK quedó instalado
/// y si la base migró es que la aplicación lo diga.
///
/// Desde `sitd-41` también se BORRA un viaje desde acá (el tacho de cada fila
/// cerrada): lo pidió Mauro después del viaje 24, que abrió el cargador de la
/// casa y quedó con dos horas y cero metros. El que está midiendo no tiene
/// tacho.
class PantallaDiagnostico extends StatefulWidget {
  final RegistroDeViajes registro;
  final String ruta;

  const PantallaDiagnostico({
    super.key,
    required this.registro,
    required this.ruta,
  });

  @override
  State<PantallaDiagnostico> createState() => _PantallaDiagnosticoState();
}

class _PantallaDiagnosticoState extends State<PantallaDiagnostico> {
  RegistroDeViajes get registro => widget.registro;

  /// Pregunta con los números del viaje a la vista —no un «¿estás seguro?»—
  /// y lo borra. No hay deshacer: por eso el cartel dice qué se va.
  Future<void> _borrar(Viaje v) async {
    final ahora = DateTime.now().millisecondsSinceEpoch;
    final que =
        '${_fecha(v.inicio)} · '
        '${v.sinMuestras ? "sin muestras" : formatearKm(v.kilometros)} · '
        '${formatearDuracion(v.duracionMs(ahora))}';
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar este viaje?'),
        content: Text(
          '$que\n\n'
          'Se borra del teléfono con sus puntos, su vibración y su audio, y '
          'si no había subido, ya no sube. No se puede deshacer. Lo que ya '
          'subió a la nube queda allá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    final ok = registro.borrarCerrado(v.id);
    if (ok) {
      bitacora.anotar(Origen.viaje, 'Borraron a mano el viaje ${v.id} ($que).');
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Viaje borrado.' : 'No se borró: el viaje sigue abierto.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final viajes = registro.ultimos();
    final ahora = DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(title: const Text('Estado')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aplicación', style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Sello $selloApp · etapa $etapa'),
                  Text(
                    'Esquema de la base en la versión ${registro.base.version}',
                  ),
                  Text(
                    '${registro.base.tablas.length} tablas: '
                    '${registro.base.tablas.join(", ")}',
                  ),
                  const SizedBox(height: 4),
                  Text(widget.ruta, style: t.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Últimos viajes', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (viajes.isEmpty)
            Text(
              'Todavía no hay ninguno. El primero se abre con «Empezar el '
              'viaje».',
              style: t.textTheme.bodySmall,
            ),
          for (final v in viajes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                v.enMarcha
                    ? Icons.play_circle_outline
                    : v.sinMuestras
                    ? Icons.signal_cellular_nodata
                    : Icons.check_circle,
                color: v.enMarcha ? t.colorScheme.primary : null,
              ),
              title: Text(
                v.sinMuestras
                    // Cero kilómetros y cero muestras no son lo mismo, y en
                    // una lista se confunden: el primero es una camioneta que
                    // no se movió, el segundo un GPS que nunca entregó nada.
                    ? 'Sin muestras · ${formatearDuracion(v.duracionMs(ahora))}'
                    : '${formatearKm(v.kilometros)} · '
                          '${formatearDuracion(v.duracionMs(ahora))}',
              ),
              subtitle: Text(
                '${_fecha(v.inicio)}'
                '${v.sinMuestras ? "" : " · ${v.muestras} muestras"}'
                '${v.cortes > 0 ? " · ${v.cortes} cortes" : ""}'
                '${v.enMarcha ? " · sin cerrar" : ""}',
              ),
              trailing: v.enMarcha
                  ? null
                  : IconButton(
                      tooltip: 'Borrar este viaje',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _borrar(v),
                    ),
            ),
        ],
      ),
    );
  }

  static String _fecha(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)} ${dos(d.hour)}:${dos(d.minute)}';
  }
}
