import 'package:flutter/material.dart';

import '../core/version.dart';
import '../features/odometro/registro.dart';
import 'formato.dart';

/// La pantalla que contesta «¿esto anda?», que era toda la aplicación en la
/// tanda 1 y ahora vive detrás del icono de información.
///
/// Sigue sirviendo para lo mismo: en un teléfono atornillado a una cabina no
/// hay consola ni depurador, y la única forma de saber qué APK quedó instalado
/// y si la base migró es que la aplicación lo diga.
class PantallaDiagnostico extends StatelessWidget {
  final RegistroDeViajes registro;
  final String ruta;

  const PantallaDiagnostico({
    super.key,
    required this.registro,
    required this.ruta,
  });

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
                  Text(ruta, style: t.textTheme.bodySmall),
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
                v.enMarcha ? Icons.play_circle_outline : Icons.check_circle,
                color: v.enMarcha ? t.colorScheme.primary : null,
              ),
              title: Text(
                '${formatearKm(v.kilometros)} · '
                '${formatearDuracion(v.duracionMs(ahora))}',
              ),
              subtitle: Text(
                '${_fecha(v.inicio)}'
                '${v.cortes > 0 ? " · ${v.cortes} cortes" : ""}'
                '${v.enMarcha ? " · sin cerrar" : ""}',
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
