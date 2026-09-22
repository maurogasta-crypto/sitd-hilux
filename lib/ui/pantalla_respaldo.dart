import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/db/base.dart';
import '../core/registro_eventos.dart';
import '../features/nube/cola.dart';
import '../features/nube/credencial.dart';
import '../features/nube/servicio_nube.dart';
import '../features/nube/subida.dart';
import '../core/version.dart';
import '../features/combustible/registro_cargas.dart';
import '../features/odometro/registro.dart';
import '../features/respaldo/reporte.dart';
import '../features/respaldo/importar.dart';
import '../features/respaldo/saneado.dart';
import '../features/sensores/satelites.dart';
import '../features/vibracion/registro_vibracion.dart';
import 'formato.dart';

/// Sacar los datos del teléfono: para arreglar algo, o para no perderlos.
///
/// **Son TRES cosas distintas y la pantalla no las mezcla nunca.** El reporte
/// para desarrollo se puede mandar por un chat porque no lleva una sola
/// coordenada; el respaldo completo lleva dónde estuvo la camioneta minuto a
/// minuto y por eso no va a ningún chat; y desde `sitd-26` el recorrido sube a
/// `recorridos/`, que es una nube con su propia regla y tampoco es un chat.
///
/// La diferencia está explicada en cada botón, no escondida en un archivo de
/// reglas — el que va a tocarlo está parado al lado de la camioneta, no
/// leyendo documentación.
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

  /// Dónde busca respaldos para volver a meter, y qué encontró.
  ///
  /// **Es la carpeta EXTERNA DE LA APLICACIÓN** —la que Android le da a cada
  /// aplicación adentro de `Android/data`— y la elección no es de comodidad:
  /// es la única a la que se llega
  /// sin pedir un permiso de almacenamiento ni agregar un selector de
  /// archivos. Este proyecto no tiene ninguno de los dos, y agregar un
  /// complemento nativo es justo lo que la verificación previa de acá NO
  /// cubre — ya costó una corrida con `permission_handler`.
  ///
  /// La contra, dicha para que no sorprenda: en Android 11 y posteriores
  /// algunos gestores de archivos de terceros no dejan entrar a
  /// `Android/data`. El del sistema sí. Si eso molesta, lo que sigue es un
  /// selector de archivos, y eso pide una tanda con la compilación al lado.
  String? _carpeta;
  List<File> _respaldos = const [];

  Future<Directory> _carpetaDeRespaldos() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory(
      p.join(
        (base ?? await getApplicationDocumentsDirectory()).path,
        'respaldos',
      ),
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _buscarRespaldos() async {
    setState(() => _trabajando = true);
    try {
      final dir = await _carpetaDeRespaldos();
      final hallados =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.db'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      if (mounted) {
        setState(() {
          _carpeta = dir.path;
          _respaldos = hallados;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resultado = 'No se pudo mirar la carpeta: $e');
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Elegir el archivo con el selector del sistema.
  ///
  /// **Es la ÚNICA forma que funciona en Android 11 y posteriores**, y no es
  /// una preferencia: se midió. Desde esa versión nadie de afuera entra a
  /// `Android/data` —ni un gestor de archivos ni Termux, probado en el Redmi
  /// 15 el 2026-09-21 con «No such file or directory»—, así que pedirle a
  /// alguien que copie un archivo a la carpeta de la aplicación es pedirle
  /// algo que su teléfono no le deja hacer.
  ///
  /// ## Y por eso NO se usa `PlatformFile.path`
  ///
  /// El selector devuelve un `content://`, no una ruta: en Android ese campo
  /// vale `null`. Usarlo habría fallado en silencio. El archivo se lee por
  /// stream —que anda con cualquier origen— y se deja en una ruta propia, que
  /// es además lo que el importador necesita.
  ///
  /// Se acepta CUALQUIER extensión a propósito: filtrar por `.db` hace que el
  /// selector esconda archivos que sí sirven, y la revisión de adentro ya
  /// rechaza lo que no es una base de esta aplicación, con un mensaje claro.
  Future<void> _elegirRespaldo() async {
    setState(() {
      _trabajando = true;
      _resultado = null;
    });
    String? copiado;
    try {
      final elegidos = await FilePicker.pickFiles(
        dialogTitle: 'Elegí el respaldo',
      );
      if (elegidos.isEmpty) return;

      final dir = await getTemporaryDirectory();
      copiado = p.join(dir.path, 'elegido.db');
      final salida = File(copiado).openWrite();
      try {
        await salida.addStream(elegidos.first.readAsByteStream());
      } finally {
        await salida.close();
      }
      if (mounted) await _importar(copiado);
    } catch (e) {
      if (mounted) {
        setState(() => _resultado = 'No se pudo leer ese archivo: $e');
      }
    } finally {
      if (copiado != null) {
        try {
          final f = File(copiado);
          if (f.existsSync()) f.deleteSync();
        } on FileSystemException {
          // El temporal que no se puede borrar no invalida nada.
        }
      }
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Meter un respaldo, con la pregunta que dice qué pasa ANTES de que pase.
  ///
  /// **Son dos caminos y el que se ofrece primero es el que no pierde nada.**
  /// Hasta `sitd-24` había uno solo —reemplazar—, pensado para el teléfono
  /// vacío. El 2026-09-21 apareció el caso común: dos juegos de viajes que no
  /// se contienen, uno en el teléfono y otro en un archivo, y la única
  /// herramienta que había obligaba a elegir cuál perder.
  ///
  /// El cartel dice los números de los DOS lados y cuántos viajes del archivo
  /// faltan acá, que es lo único con lo que alguien puede decidir. «¿Estás
  /// seguro?» no es una pregunta: no dice qué pasa si uno contesta que sí.
  Future<void> _importar(String ruta) async {
    final revision = revisarRespaldo(viva: widget.base, ruta: ruta);
    if (!mounted) return;
    if (!revision.sePuede) {
      setState(() => _resultado = revision.problema);
      return;
    }
    final trae = revision.candidato!;
    final forma = await showDialog<_FormaDeMeter>(
      context: context,
      builder: (c) {
        final chico = Theme.of(c).textTheme.bodySmall;
        return AlertDialog(
          title: const Text('Meter el respaldo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Este teléfono tiene ahora:\n${revision.actual.resumen}.'),
                const SizedBox(height: 10),
                Text('El respaldo trae:\n${trae.resumen}.'),
                const SizedBox(height: 10),
                Text(
                  revision.sumarTraeAlgo
                      ? 'De esos, ${revision.viajesNuevos} '
                            '${revision.viajesNuevos == 1 ? 'viaje no está' : 'viajes no están'} '
                            'en el teléfono.'
                      : 'Todos esos viajes ya están en el teléfono: sumar no '
                            'traería nada nuevo.',
                ),
                const SizedBox(height: 14),
                Text(
                  revision.sumarTraeAlgo
                      ? 'SUMAR los junta y no pierde nada: quedarían '
                            '${revision.viajesDespuesDeSumar} viajes.'
                      : 'SUMAR no haría nada, y tampoco rompería nada.',
                  style: chico,
                ),
                const SizedBox(height: 6),
                Text(
                  'REEMPLAZAR deja SÓLO lo del respaldo: lo que este teléfono '
                  'tiene ahora se pierde y no hay papelera. Si todavía no lo '
                  'guardaste, cancelá y sacá una copia primero.',
                  style: chico,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, _FormaDeMeter.reemplazar),
              child: const Text('Reemplazar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, _FormaDeMeter.sumar),
              child: const Text('Sumar'),
            ),
          ],
        );
      },
    );
    if (forma == null) return;

    try {
      final dir = await getTemporaryDirectory();
      final String texto;
      if (forma == _FormaDeMeter.sumar) {
        final r = sumarRespaldo(
          viva: widget.base,
          ruta: ruta,
          carpetaDeTrabajo: dir.path,
        );
        texto = r.salioBien && !r.nadaNuevo
            ? '${r.resumen} Quedaron '
                  '${revisarRespaldo(viva: widget.base, ruta: ruta).actual.resumen}. '
                  'Volvé a la pantalla principal para verlos.'
            : r.resumen;
      } else {
        final problema = importarRespaldo(
          viva: widget.base,
          ruta: ruta,
          carpetaDeTrabajo: dir.path,
        );
        final ahora = revisarRespaldo(viva: widget.base, ruta: ruta).actual;
        texto =
            problema ??
            'Listo: quedaron ${ahora.resumen}. Volvé a la pantalla '
                'principal para verlos.';
      }
      if (mounted) setState(() => _resultado = texto);
    } catch (e) {
      if (mounted) setState(() => _resultado = 'No se pudo importar: $e');
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

      // Qué buscar después, leído de la base VIVA y antes de tocar la copia.
      final secretos = valoresQueNoSalen(widget.base);

      final copia = await File(widget.ruta).copy(p.join(dir.path, nombre));

      // SANEAR, que es sacarlo, y COMPROBAR, que es otra cosa. Ver
      // `saneado.dart`: un `DELETE` de SQLite deja el texto en el archivo, así
      // que lo que vale es lo que digan los bytes.
      //
      // Las dos son sincrónicas y bloquean la pantalla mientras corren, igual
      // que el `wal_checkpoint` de arriba. Sobre una base de unos megabytes se
      // mide en milisegundos; si algún día el respaldo pesa de verdad, esto es
      // lo primero que hay que mandar a un isolate.
      final sacadas = sanearCopia(copia.path);
      final quedo = loQueSeEscapa(copia.path, secretos);
      if (quedo != null) {
        // No se comparte nada. Es el único final posible: compartir igual y
        // avisar sería avisar de algo que ya salió del teléfono.
        await copia.delete();
        if (mounted) {
          setState(
            () => _resultado =
                'NO se compartió: el saneado no pudo sacar una credencial de '
                'la copia. Es una falla del programa, no tuya — reportala '
                'desde acá y no compartas respaldos hasta que esté arreglada.',
          );
        }
        return;
      }

      final tamano = await copia.length();

      /* Y queda una copia en la carpeta desde la que se puede VOLVER A
         METER. Sin esto, el camino de ida funciona y el de vuelta depende de
         que el gestor de archivos del teléfono llegue a `Android/data`. */
      try {
        await copia.copy(p.join((await _carpetaDeRespaldos()).path, nombre));
      } catch (_) {
        // Que no se pueda dejar la copia local no invalida compartirla.
      }

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
        final nota = sacadas.isEmpty
            ? ''
            : ' · sin credenciales (${sacadas.length})';
        setState(
          () => _resultado =
              '$nombre · ${(tamano / 1024 / 1024).toStringAsFixed(1)} MB$nota',
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
            if (widget.nube != null)
              _Recorridos(
                nube: widget.nube!,
                guarda: widget.guarda!,
                base: widget.base,
              ),
            if (widget.nube != null) const SizedBox(height: 12),
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
                'Una copia del archivo de la base, con los viajes, las '
                'cargas y las vibraciones. Es el respaldo de verdad: si el '
                'teléfono se pierde o se rompe, esto es lo único que los '
                'devuelve.\n\n'
                'LLEVA EL RECORRIDO: dónde estuvo la camioneta, minuto a '
                'minuto. Va a Drive, a una computadora o a una tarjeta — no a '
                'un chat.\n\n'
                'NO lleva la contraseña de la nube ni la sesión: se sacan de '
                'la copia antes de compartirla, y si no se pudieran sacar no '
                'se comparte nada.\n\n'
                'Queda además una copia en el teléfono, en la carpeta desde '
                'la que se puede volver a meter.',
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
          const SizedBox(height: 12),
          _Opcion(
            icono: Icons.settings_backup_restore,
            titulo: 'Volver a meter un respaldo',
            texto:
                'SUMAR junta los viajes del archivo con los que ya tiene este '
                'teléfono, sin perder ninguno de los dos lados. Los que ya '
                'estén no se duplican, así que meter dos veces el mismo '
                'archivo no rompe nada.\n\n'
                'REEMPLAZAR deja sólo lo del archivo, y es para un teléfono '
                'vacío. Antes de tocar nada te dice qué pasa con cada una, con '
                'los números de los dos lados.\n\n'
                'La configuración de la nube NO se toca en ninguno de los dos '
                'casos: la que vale es la que este teléfono tiene ahora.',
            boton: 'Elegir el archivo',
            onPressed: _trabajando ? null : _elegirRespaldo,
          ),
          const SizedBox(height: 8),
          Text(
            'Se abre el selector del teléfono: buscá el .db donde lo tengas — '
            'Descargas, Drive, una tarjeta. Desde Android 11 ésta es la única '
            'forma que funciona, porque el sistema no deja que nadie de afuera '
            'entre a la carpeta de la aplicación.',
            style: t.textTheme.bodySmall?.copyWith(
              color: t.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _trabajando ? null : _buscarRespaldos,
              child: const Text('o mirar los que guardó esta pantalla'),
            ),
          ),
          if (_carpeta != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _respaldos.isEmpty
                    ? 'No hay ninguno guardado todavía. Los respaldos que saca '
                          'esta pantalla quedan acá y aparecen en esta lista. '
                          'Para uno que esté en otro lado, usá «Elegir el '
                          'archivo».'
                    : 'Guardados en el teléfono:',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
            ),
          for (final r in _respaldos)
            Card(
              child: ListTile(
                title: Text(p.basename(r.path)),
                subtitle: Text(
                  '${(r.statSync().size / 1024 / 1024).toStringAsFixed(1)} MB',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _trabajando ? null : () => _importar(r.path),
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

/// Las dos formas de meter un respaldo. Están acá y no en `importar.dart`
/// porque son una pregunta de pantalla: el módulo expone las dos funciones y
/// no sabe cuál eligió nadie.
enum _FormaDeMeter { sumar, reemplazar }

/// El recorrido en la nube: subirlo a mano, y volver a bajarlo.
///
/// ## Por qué esta tarjeta existe y está separada de la de arriba
///
/// La de arriba sube sola el reporte SIN coordenadas. Ésta sube **dónde
/// estuvo la camioneta**, y lo hace únicamente cuando alguien toca el botón.
///
/// Son dos tarjetas y no una a propósito: el que las mira está parado al lado
/// de la camioneta y tiene que poder ver de un vistazo cuál es cuál. Es la
/// misma decisión que separa el reporte del respaldo más abajo en esta misma
/// pantalla, y por el mismo motivo.
class _Recorridos extends StatefulWidget {
  final ServicioNube nube;
  final GuardaDeCredencial guarda;
  final Base base;

  const _Recorridos({
    required this.nube,
    required this.guarda,
    required this.base,
  });

  @override
  State<_Recorridos> createState() => _RecorridosState();
}

class _RecorridosState extends State<_Recorridos> {
  bool _trabajando = false;
  String? _resultado;
  List<RecorridoEnLaNube>? _arriba;

  Future<void> _subir() async {
    setState(() {
      _trabajando = true;
      _resultado = null;
    });
    final t = await widget.nube.subirRecorridos();
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      _resultado = t.resumen;
    });
    await _mirar(callado: true);
  }

  /// Pregunta qué hay arriba. Con [callado] no toca el mensaje de resultado,
  /// para no pisar lo que acaba de decir la subida.
  Future<void> _mirar({bool callado = false}) async {
    final c = widget.guarda.credencial;
    if (c == null) return;
    if (!callado) setState(() => _trabajando = true);
    final lista = await widget.nube.subida.listarRecorridos(
      credencial: c,
      sesion: widget.nube.sesion,
    );
    if (!mounted) return;
    setState(() {
      _arriba = lista;
      _trabajando = false;
      if (!callado && lista.isEmpty) {
        _resultado = 'No hay ningún recorrido en la nube todavía.';
      }
    });
  }

  Future<void> _bajar(RecorridoEnLaNube r) async {
    final c = widget.guarda.credencial;
    if (c == null) return;
    setState(() {
      _trabajando = true;
      _resultado = null;
    });
    final b = await widget.nube.subida.bajarRecorrido(
      credencial: c,
      id: r.id,
      sesion: widget.nube.sesion,
    );
    if (!mounted) return;
    if (!b.hay) {
      setState(() {
        _trabajando = false;
        _resultado = b.noEstaba
            ? 'Ese recorrido ya no está en la nube.'
            : b.falla;
      });
      return;
    }
    // Meterlo en la base es sincrónico y corto: son unos miles de INSERT
    // adentro de una transacción.
    final hecho = meterViajeDeLaNube(
      viva: widget.base,
      recorrido: b.texto!,
      ficha: b.ficha,
    );
    setState(() {
      _trabajando = false;
      _resultado = hecho.resumen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.guarda.credencial;
    final lista = _arriba;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: t.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'El recorrido en la nube',
                    style: t.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sube DÓNDE ESTUVO la camioneta, punto por punto, con la ficha '
              'del viaje al lado. Es lo que deja bajar un viaje entero a otro '
              'teléfono, y lo que deja cruzar todos los datos desde el chat.\n\n'
              'No sube solo: sube cuando tocás el botón. Y una vez que un '
              'recorrido está arriba, sacarlo de ahí se hace desde la consola '
              'de Firebase — esta aplicación no lo borra.',
              style: t.textTheme.bodySmall,
            ),
            if (_resultado != null) ...[
              const SizedBox(height: 10),
              Text(_resultado!, style: t.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _trabajando || c == null ? null : () => _mirar(),
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('Ver qué hay'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _trabajando || c == null ? null : _subir,
                    icon: _trabajando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Subir'),
                  ),
                ),
              ],
            ),
            if (c == null) ...[
              const SizedBox(height: 8),
              Text(
                'Falta configurar la nube, acá arriba.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
            ],
            if (lista != null && lista.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'En la nube — tocá uno para traerlo a este teléfono:',
                style: t.textTheme.bodySmall?.copyWith(
                  color: t.colorScheme.outline,
                ),
              ),
              for (final r in lista)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(formatearFechaYHora(r.inicio)),
                  subtitle: Text(
                    '${r.puntos} ${r.puntos == 1 ? 'punto' : 'puntos'}',
                  ),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: _trabajando ? null : () => _bajar(r),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
