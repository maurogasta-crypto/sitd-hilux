import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/db/base.dart';
import 'core/version.dart';

/// Tanda 1: el esqueleto.
///
/// Esta pantalla no mide nada todavia. Lo que hace es contestar la unica
/// pregunta que importa en esta etapa: **si la cadena entera funciona en el
/// telefono**. Que el APK que compilo GitHub Actions se instale, arranque,
/// abra la base en el almacenamiento de la aplicacion, corra las migraciones y
/// diga en que version quedo.
///
/// Si esto anda en el Redmi Note 9, todo lo demas es agregar funciones. Si no
/// anda, no tiene sentido escribir una linea mas.
void main() {
  runApp(const AppSitd());
}

class AppSitd extends StatelessWidget {
  const AppSitd({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SITD Hilux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PantallaArranque(),
    );
  }
}

/// Lo que se pudo averiguar de la base al arrancar.
class EstadoBase {
  final int version;
  final List<String> tablas;
  final String ruta;
  final String? error;

  const EstadoBase({
    required this.version,
    required this.tablas,
    required this.ruta,
    this.error,
  });
}

Future<EstadoBase> _abrirBase() async {
  var ruta = '(sin resolver)';
  try {
    final dir = await getApplicationDocumentsDirectory();
    ruta = p.join(dir.path, 'sitd.db');
    final base = Base.abrir(ruta);
    final estado = EstadoBase(
      version: base.version,
      tablas: base.tablas,
      ruta: ruta,
    );
    base.cerrar();
    return estado;
  } catch (e) {
    return EstadoBase(version: -1, tablas: const [], ruta: ruta, error: '$e');
  }
}

class PantallaArranque extends StatefulWidget {
  const PantallaArranque({super.key});

  @override
  State<PantallaArranque> createState() => _PantallaArranqueState();
}

class _PantallaArranqueState extends State<PantallaArranque> {
  late final Future<EstadoBase> _base = _abrirBase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SITD Hilux'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$selloApp · etapa $etapa',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<EstadoBase>(
        future: _base,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final e = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Ficha(
                titulo: 'Base local',
                bien: e.error == null,
                lineas: e.error != null
                    ? ['No abrio', e.error!]
                    : [
                        'Esquema en la version ${e.version}',
                        '${e.tablas.length} tablas: ${e.tablas.join(", ")}',
                        e.ruta,
                      ],
              ),
              const SizedBox(height: 12),
              const _Ficha(
                titulo: 'Que falta',
                bien: false,
                lineas: [
                  'Tanda 2: servicio en primer plano y odometria GPS en vivo.',
                  'Esta tanda solo comprueba que el APK se instala, arranca y '
                      'migra la base en el telefono.',
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Ficha extends StatelessWidget {
  final String titulo;
  final bool bien;
  final List<String> lineas;

  const _Ficha({
    required this.titulo,
    required this.bien,
    required this.lineas,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  bien ? Icons.check_circle : Icons.info_outline,
                  size: 20,
                  color: bien ? Colors.green : t.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(titulo, style: t.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in lineas)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l, style: t.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
