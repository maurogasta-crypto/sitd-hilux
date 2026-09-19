import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/db/base.dart';
import '../core/registro_eventos.dart';
import '../features/nube/cola.dart';
import '../features/nube/credencial.dart';
import '../features/nube/servicio_nube.dart';
import '../core/version.dart';
import '../features/combustible/registro_cargas.dart';
import '../features/odometro/registro.dart';
import '../features/respaldo/reporte.dart';
import '../features/sensores/satelites.dart';
import '../features/vibracion/registro_vibracion.dart';

/// Sacar los datos del teléfono: para arreglar algo, o para no perderlos.
///
/// **Son dos cosas distintas y la pantalla no las mezcla nunca.** El reporte
/// para desarrollo se puede mandar por un chat porque no lleva una sola
/// coordenada; el respaldo completo lleva dónde estuvo la camioneta minuto a
/// minuto y por eso no va a ningún chat. La diferencia está explicada en cada
/// botón, no escondida en un archivo de reglas — el que va a tocarlo está
/// parado al lado de la camioneta, no leyendo documentación.
class PantallaRespaldo extends StatefulWidget {
  final Base base;
  final RegistroDeViajes viajes;
  final RegistroDeCargas cargas;
  final RegistroDeVibracion vibraciones;
  final String ruta;

  /// La bitácora EN DISCO. El reporte la lee de acá y no de la memoria: el
  /// primer reporte real salió con la bitácora vacía porque se generó dos
  /// horas después del viaje, con la aplicación reabierta en el medio.
  final RegistroDeEventos? eventos;

  /// La cola de viajes que faltan subir y el que los sube. Opcionales: el
  /// banco arma la pantalla sin nube.
  final ColaDeSubida? cola;
  final ServicioNube? nube;

  /// Dónde se guarda la configuración de la nube, que Mauro pega a mano.
  final GuardaDeCredencial? guarda;

  /// La escucha del motor GNSS, que ahora arranca con la aplicación. Antes la
  /// encendía sólo la pantalla de sensores, así que el reporte salía diciendo
  /// «no disponible» cuando nadie la había abierto.
  final Satelites? satelites;

  const PantallaRespaldo({
    super.key,
    required this.base,
    required this.viajes,
    required this.cargas,
    required this.vibraciones,
    required this.ruta,
    this.eventos,
    this.satelites,
    this.cola,
    this.nube,
    this.guarda,
  });

  @override
  State<PantallaRespaldo> createState() => _PantallaRespaldoState();
}

class _PantallaRespaldoState extends State<PantallaRespaldo> {
  String? _resultado;
  bool _trabajando = false;

  static String _fechaDeArchivo(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${dos(d.month)}-${dos(d.day)}-${dos(d.hour)}${dos(d.minute)}';
  }

  Future<void> _compartirReporte(Alcance alcance) async {
    setState(() {
      _trabajando = true;
      _resultado = null;
    });
    try {
      final cielo = await widget.satelites?.leer();
      final mapa = armarReporte(
        base: widget.base,
        viajes: widget.viajes,
        cargas: widget.cargas,
        vibraciones: widget.vibraciones,
        alcance: alcance,
        sello: selloApp,
        ahora: DateTime.now().millisecondsSinceEpoch,
        eventos: widget.eventos,
        satelites: cielo,
      );
      final texto = const JsonEncoder.withIndent('  ').convert(mapa);
      final dir = await getTemporaryDirectory();
      final nombre =
          'sitd-${alcance == Alcance.paraDesarrollo ? "reporte" : "datos"}'
          '-${_fechaDeArchivo(DateTime.now())}.json';
      final archivo = File(p.join(dir.path, nombre));
      await archivo.writeAsString(texto);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path)],
          subject: 'SITD Hilux · $nombre',
          text: alcance == Alcance.paraDesarrollo
              ? 'Reporte de SITD Hilux ($selloApp). No lleva posiciones.'
              : 'Datos completos de SITD Hilux ($selloApp). LLEVA EL '
                    'RECORRIDO: no lo pegues en un chat.',
        ),
      );
      if (mounted) {
        setState(
          () => _resultado =
              '$nombre · ${(texto.length / 1024).toStringAsFixed(0)} KB',
        );
      }
    } catch (e) {
      // Un error acá se muestra con su causa: «no se pudo compartir» no se
      // puede diagnosticar.
      if (mounted) setState(() => _resultado = 'No se pudo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// El respaldo de verdad: una copia del archivo de la base.
  ///
  /// **Antes de copiar hay que cerrar el WAL.** En modo WAL lo último que se
  /// escribió vive en un archivo aparte (`sitd.db-wal`) hasta que SQLite lo
  /// pasa al principal: copiar `sitd.db` sin hacer eso se lleva una base sin
  /// los viajes de hoy, y eso no se nota hasta el día que haga falta.
  Future<void> _compartirLaBase() async {
    setState(() {
      _trabajando = true;
      _resultado = null;
    });
    try {
      widget.base.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      final dir = await getTemporaryDirectory();
      final nombre = 'sitd-${_fechaDeArchivo(DateTime.now())}.db';
      final copia = await File(widget.ruta).copy(p.join(dir.path, nombre));
      final tamano = await copia.length();

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(copia.path)],
          subject: 'SITD Hilux · respaldo $nombre',
          text:
              'Copia de la base de SITD Hilux. LLEVA EL RECORRIDO: '
              'guardala, no la pegues en un chat.',
        ),
      );
      if (mounted) {
        setState(
          () => _resultado =
              '$nombre · ${(tamano / 1024 / 1024).toStringAsFixed(1)} MB',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _resultado = 'No se pudo: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sacar los datos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (widget.cola != null && widget.guarda != null) ...[
            _Nube(
              cola: widget.cola!,
              nube: widget.nube,
              guarda: widget.guarda!,
            ),
            const SizedBox(height: 12),
          ],
          _Opcion(
            icono: Icons.bug_report_outlined,
            titulo: 'Reporte para desarrollo',
            texto:
                'Todo lo que hace falta para entender qué pasó y ajustar el '
                'código: kilómetros, contadores, por qué se descartó cada '
                'muestra, un resumen estadístico de las velocidades y '
                'precisiones, los vectores de vibración y las cargas.\n\n'
                'NO lleva ni una coordenada, y hay una prueba en el banco que '
                'lo comprueba sobre el texto entero del archivo. Se puede '
                'mandar por donde sea.',
            boton: 'Compartir el reporte',
            onPressed: _trabajando
                ? null
                : () => _compartirReporte(Alcance.paraDesarrollo),
          ),
          const SizedBox(height: 12),
          _Opcion(
            icono: Icons.save_outlined,
            titulo: 'Respaldo completo',
            texto:
                'Una copia del archivo de la base, tal cual está. Es el '
                'respaldo de verdad: si el teléfono se pierde o se rompe, esto '
                'es lo único que devuelve los viajes.\n\n'
                'LLEVA EL RECORRIDO: dónde estuvo la camioneta, minuto a '
                'minuto. Va a Drive, a una computadora o a una tarjeta — no a '
                'un chat.',
            boton: 'Guardar una copia',
            peligroso: true,
            onPressed: _trabajando ? null : _compartirLaBase,
          ),
          const SizedBox(height: 12),
          if (_trabajando) const LinearProgressIndicator(),
          if (_resultado != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_resultado!, style: t.textTheme.bodyMedium),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Todavía no hay forma de VOLVER a meter un respaldo en el '
            'teléfono: eso necesita una sesión con la cadena de compilación. '
            'Está anotado y no se olvidó — pero guardar es lo urgente, porque '
            'lo que no se guardó no se puede restaurar después.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  final String boton;
  final VoidCallback? onPressed;
  final bool peligroso;

  const _Opcion({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.boton,
    required this.onPressed,
    this.peligroso = false,
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
                  icono,
                  color: peligroso
                      ? t.colorScheme.error
                      : t.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(titulo, style: t.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(texto, style: t.textTheme.bodySmall),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: peligroso
                  ? OutlinedButton(onPressed: onPressed, child: Text(boton))
                  : FilledButton(onPressed: onPressed, child: Text(boton)),
            ),
          ],
        ),
      ),
    );
  }
}

/// La subida automática: qué falta, qué se subió, y dónde se pega la
/// configuración.
///
/// **La configuración se teclea y no viene en el APK.** El repositorio es
/// público y el APK se descarga sin cuenta, así que una contraseña metida
/// adentro sería un dato público. Se pega una vez, vive en el SQLite de la
/// aplicación y no entra al repositorio ni a un chat.
class _Nube extends StatefulWidget {
  final ColaDeSubida cola;
  final ServicioNube? nube;
  final GuardaDeCredencial guarda;

  const _Nube({required this.cola, required this.nube, required this.guarda});

  @override
  State<_Nube> createState() => _NubeState();
}

class _NubeState extends State<_Nube> {
  bool _subiendo = false;
  String? _resultado;

  Future<void> _subirAhora() async {
    setState(() {
      _subiendo = true;
      _resultado = null;
    });
    final t = await widget.nube?.subirPendientes();
    if (!mounted) return;
    setState(() {
      _subiendo = false;
      _resultado = t == null
          ? 'No hay nada configurado todavía.'
          : !t.huboAlgo
          ? 'No había nada para subir.'
          : t.fallaron == 0
          ? 'Listo: ${t.subidos} subidos.'
          : '${t.subidos} subidos, ${t.fallaron} quedaron esperando. '
                '${t.primeraFalla ?? ""}';
    });
  }

  Future<void> _configurar() async {
    final campo = TextEditingController(
      text: widget.guarda.credencial == null ? moldeDeCredencial : '',
    );
    final pegado = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Configurar la nube'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pegá acá la configuración completa, tal como la tenés guardada '
              'en el gestor de contraseñas. Son cuatro datos en un solo '
              'texto.\n\nNo se sube a ningún repositorio ni se manda por '
              'ningún chat: queda sólo en este teléfono.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: campo,
              maxLines: 7,
              autofocus: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, campo.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    campo.dispose();
    if (pegado == null || !mounted) return;

    final error = widget.guarda.guardar(pegado);
    setState(() => _resultado = error ?? 'Configuración guardada.');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.guarda.credencial;
    final faltan = widget.cola.cuantosFaltan;
    final subidos = widget.cola.cuantosSubidos;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: t.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Subida automática',
                    style: t.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c == null
                  ? 'Sin configurar. Los viajes se van guardando en la cola '
                        'igual, así que no se pierde nada: cuando configures, '
                        'suben todos.'
                  : 'Cada viaje que termina se sube solo cuando hay señal. '
                        'Sube el reporte SIN coordenadas — el mismo que se '
                        'puede mandar por un chat.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Cuenta(numero: faltan, rotulo: 'esperando'),
                const SizedBox(width: 24),
                _Cuenta(numero: subidos, rotulo: 'subidos'),
              ],
            ),
            if (c != null) ...[
              const SizedBox(height: 8),
              Text(
                c.resumen,
                style: t.textTheme.labelSmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
            ],
            if (_resultado != null) ...[
              const SizedBox(height: 10),
              Text(_resultado!, style: t.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _subiendo ? null : _configurar,
                    icon: const Icon(Icons.key_outlined),
                    label: Text(c == null ? 'Configurar' : 'Cambiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _subiendo || c == null ? null : _subirAhora,
                    icon: _subiendo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_outlined),
                    label: const Text('Subir ahora'),
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

class _Cuenta extends StatelessWidget {
  final int numero;
  final String rotulo;

  const _Cuenta({required this.numero, required this.rotulo});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$numero', style: t.textTheme.headlineSmall),
        const SizedBox(width: 6),
        Text(
          rotulo,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
        ),
      ],
    );
  }
}
