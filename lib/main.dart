import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'core/arranque.dart';
import 'core/bitacora.dart';
import 'features/nube/credencial.dart';
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
  escucharErroresDelSistema();
  final arranque = await Arranque.abrir();
  runApp(AppSitd(arranque: arranque));
}

/// Manda a la bitácora los errores que hoy se iban a una consola que nadie
/// mira (`sitd-33`).
///
/// **Existe por el modo «Normal» del GPS**, que no entregó nunca en el Redmi
/// 15 y nunca dijo por qué. Cuando un complemento falla adentro de un canal de
/// eventos, Flutter no mete el error en el stream: lo reporta con
/// `FlutterError.reportError`, y eso por defecto sólo se imprime. La cascada
/// sí anota los errores del stream —«el modo X falló»— y esa línea no apareció
/// ni una vez en once viajes: el error no le llegó. Es la misma lección que
/// `hasSpeed`: una biblioteca puede fallar en silencio, y un sensor mudo se ve
/// igual que uno roto.
///
/// Se anota con [Bitacora.anotarSiCambio] y no con `anotar`: un error de
/// dibujo se repite en cada cuadro, y sin eso llenaría el anillo de 300 líneas
/// en cinco segundos y se llevaría puesto justo lo que había que leer. Y se
/// sigue imprimiendo como siempre: esto AGREGA un destino, no saca el otro.
void escucharErroresDelSistema() {
  final anterior = FlutterError.onError;
  FlutterError.onError = (detalle) {
    bitacora.anotarSiCambio(Origen.sistema, textoDeError(detalle));
    (anterior ?? FlutterError.presentError)(detalle);
  };
  PlatformDispatcher.instance.onError = (error, pila) {
    bitacora.anotarSiCambio(
      Origen.sistema,
      'Error sin atajar: ${recortarError('$error')}',
    );
    // `false` deja que siga su camino de siempre: no se esconde nada.
    return false;
  };
}

/// Lo que se anota de un error de Flutter: dónde pasó y qué dijo.
///
/// El «dónde» importa más que el «qué» para lo que esto vino a resolver: un
/// canal que falla dice `while activating platform stream on channel …`, y ese
/// nombre de canal es lo que dice QUÉ complemento fue.
String textoDeError(FlutterErrorDetails d) {
  final contexto = d.context?.toDescription();
  final donde = contexto == null || contexto.isEmpty ? '' : ' ($contexto)';
  return 'Error del sistema$donde: ${recortarError(d.exceptionAsString())}';
}

/// Un error puede traer una pila de doscientas líneas; a la bitácora va el
/// principio, que es lo que dice qué pasó.
String recortarError(String texto, {int largo = 300}) {
  final uno = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
  return uno.length <= largo ? uno : '${uno.substring(0, largo)}…';
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
              modoRecordado: arranque.modoRecordado,
              cola: arranque.cola,
              nube: arranque.nube,
              guarda: arranque.base == null
                  ? null
                  : GuardaDeCredencial(arranque.base!),
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
