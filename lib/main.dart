import 'package:flutter/material.dart';

import 'core/arranque.dart';
import 'core/version.dart';
import 'ui/pantalla_viaje.dart';

/// Tanda 2: la odometría en vivo.
///
/// La base se abre y se migra **antes** de dibujar nada, porque toda la
/// pantalla depende de ella y un `FutureBuilder` alrededor de la aplicación
/// entera es un estado más que mantener. Lo que no se hace acá es pedir
/// permisos: los de ubicación se piden cuando alguien toca «Empezar el viaje»,
/// que es cuando se entiende para qué son — y porque nada que dependa de un
/// permiso puede correr al abrir.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final arranque = await Arranque.abrir();
  runApp(AppSitd(arranque: arranque));
}

class AppSitd extends StatelessWidget {
  final Arranque arranque;

  const AppSitd({super.key, required this.arranque});

  @override
  Widget build(BuildContext context) {
    final servicio = arranque.servicio;
    final registro = arranque.registro;
    final cargas = arranque.cargas;
    final vibraciones = arranque.vibraciones;
    final vibracion = arranque.vibracion;
    final despierta = arranque.despierta;
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
      home:
          servicio == null ||
              registro == null ||
              cargas == null ||
              vibraciones == null ||
              vibracion == null ||
              despierta == null
          ? _SinBase(error: arranque.error, ruta: arranque.ruta)
          : PantallaViaje(
              servicio: servicio,
              registro: registro,
              cargas: cargas,
              vibraciones: vibraciones,
              vibracion: vibracion,
              despierta: despierta,
              gps: arranque.gps,
              eventos: arranque.eventos,
              satelites: arranque.satelites,
              base: arranque.base!,
              ruta: arranque.ruta,
            ),
    );
  }
}

/// Si la base no abre no hay nada que medir, y lo único útil que puede hacer
/// la aplicación es decir por qué con la causa a la vista.
class _SinBase extends StatelessWidget {
  final String? error;
  final String ruta;

  const _SinBase({required this.error, required this.ruta});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('SITD Hilux')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('La base local no abrió', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Sin base no se puede guardar un viaje, así que la aplicación no '
              'arranca a medir. Esto es lo que dijo el sistema:',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(
              error ?? 'sin detalle',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(ruta, style: t.textTheme.bodySmall),
            const Spacer(),
            Text('$selloApp · etapa $etapa', style: t.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
