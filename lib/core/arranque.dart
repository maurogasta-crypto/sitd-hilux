import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/audio/fuente_audio.dart';
import '../features/audio/registro_audio.dart';
import '../features/audio/servicio_audio.dart';
import '../features/calibracion/calibracion.dart';
import '../features/combustible/registro_cargas.dart';
import '../features/enlace/enlace.dart';
import '../features/grabacion/grabacion.dart';
import '../features/motor/cargador.dart';
import '../features/odometro/cascada.dart';
import '../features/odometro/modo_recordado.dart';
import '../features/odometro/pantalla_despierta.dart';
import '../features/vibracion/fuente_vibracion.dart';
import '../features/vibracion/analisis.dart' show deLaClaseVigente;
import '../features/vibracion/lineas.dart';
import '../features/vibracion/registro_vibracion.dart';
import '../features/vibracion/servicio_vibracion.dart';
import '../features/nube/cola.dart';
import '../features/nube/credencial.dart';
import '../features/nube/reintento.dart';
import '../features/nube/servicio_nube.dart';
import '../features/nube/sesion.dart';
import '../features/nube/subida.dart';
import '../features/odometro/registro.dart';
import '../features/respaldo/reporte.dart';
import 'version.dart';
import '../features/sensores/satelites.dart';
import '../features/odometro/servicio.dart';
import 'aparato.dart';
import 'bitacora.dart';
import 'db/base.dart';
import 'registro_eventos.dart';

/// Lo que se arma una sola vez al abrir la aplicación, antes de dibujar nada.
///
/// Está acá y no adentro de un widget porque abrir la base y migrarla es
/// trabajo que se hace una vez y no en cada reconstrucción de la pantalla. Y
/// **no pide ningún permiso**: los de ubicación se piden recién cuando alguien
/// toca «Empezar el viaje», que es cuando se entiende para qué son.
class Arranque {
  final Base? base;
  final String ruta;

  /// Lo que dijo el sistema si la base no abrió. Se muestra tal cual: un error
  /// sin causa no se puede diagnosticar.
  final String? error;

  final RegistroDeViajes? registro;
  final RegistroDeCargas? cargas;
  final RegistroDeVibracion? vibraciones;
  final PantallaDespierta? despierta;
  final ServicioOdometria? servicio;
  final ServicioVibracion? vibracion;

  /// `sitd-37`, etapa E: el micrófono, y el cargador que dice si el motor
  /// está encendido.
  final RegistroDeAudio? audios;
  final ServicioAudio? audio;
  final Stream<AvisoCarga>? cargador;

  /// La cascada de modos del GPS, para que la pantalla muestre cuál quedó
  /// puesto y cómo quedó el permiso de notificaciones.
  final FuenteEnCascada? gps;

  /// La bitácora en disco. El reporte la lee de acá y no de la memoria: lo de
  /// la memoria se pierde al cerrar la aplicación, y el reporte se genera
  /// horas después del viaje.
  final RegistroDeEventos? eventos;

  /// La escucha del motor GNSS. **Arranca con la aplicación y no con la
  /// pantalla de sensores**: en `sitd-12` sólo la encendía esa pantalla, así
  /// que el primer reporte real salió con «satélites: no disponible» — no
  /// porque el teléfono no contestara, sino porque nadie había preguntado.
  final Satelites? satelites;

  /// El modo de GPS que funcionó la última vez. La pantalla de sensores lo usa
  /// como valor inicial de su selector.
  final ModoRecordado? modoRecordado;

  /// La cola de viajes que faltan subir, y el que los sube.
  final ColaDeSubida? cola;
  final ServicioNube? nube;

  /// Las grabaciones de 10 s (`sitd-55`): el botón «Grabar 10 s» lo usa.
  final Grabador? grabador;

  const Arranque._({
    required this.ruta,
    this.base,
    this.error,
    this.registro,
    this.cargas,
    this.vibraciones,
    this.despierta,
    this.servicio,
    this.vibracion,
    this.audios,
    this.audio,
    this.cargador,
    this.gps,
    this.eventos,
    this.satelites,
    this.modoRecordado,
    this.cola,
    this.nube,
    this.grabador,
  });

  bool get anduvo => base != null;

  List<String> get tablas => base?.tablas ?? const [];
  int get version => base?.version ?? -1;

  static Future<Arranque> abrir() async {
    var ruta = '(sin resolver)';
    try {
      final dir = await getApplicationDocumentsDirectory();
      ruta = p.join(dir.path, 'sitd.db');
      final base = Base.abrir(ruta);
      // Lo primero: enganchar la bitácora al disco. De acá en adelante todo lo
      // que se anote sobrevive a que el sistema mate la aplicación.
      final eventos = RegistroDeEventos(base);
      bitacora.alDisco = eventos.guardar;
      bitacora.anotar(
        Origen.sistema,
        'Aplicación abierta. Base en la versión ${base.version}.',
      );
      // sitd-44: el modelo del teléfono, para que cada viaje diga dónde se
      // midió. No se espera: si el canal no contesta, abre igual.
      unawaited(anotarTelefono(base));
      // sitd-45: la vuelta de rueda medida en el garage, si la hay, pasa a
      // ser la que usa la lectura del espectro y las RPM por marcha.
      RegistroDeCalibraciones(base).aplicarRueda();
      final satelites = Satelites();
      // No se espera: si el canal tarda o no está, la aplicación abre igual.
      unawaited(satelites.arrancar());
      // Y se lee de fondo, cada medio minuto, mientras la aplicación viva
      // (`sitd-36`). Hasta ahí sólo leía la pantalla de sensores, y manejando
      // nadie la abre: el reporte y la bitácora quedaban en «sin arrancar».
      // Es una llamada al canal cada 30 s: no se nota ni en un Helio G85.
      Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(satelites.sondear()),
      );
      final registro = RegistroDeViajes(base);
      final cargas = RegistroDeCargas(base);
      final vibraciones = RegistroDeVibracion(base);
      final audios = RegistroDeAudio(base);
      final grabaciones = RegistroDeGrabaciones(base);
      final cola = ColaDeSubida(base);
      // sitd-50: Sincronizar corre solo, al abrir y al cerrar cada viaje.
      // El servicio de la nube se arma más abajo; el cierre lo usa recién
      // cuando un viaje termina, y para entonces ya existe.
      late final ServicioNube nube;
      // sitd-55: si no terminó bien, se reintenta cuando vuelve la señal.
      final reintento = Reintento();
      Future<void> sincronizarSolo(String cuando) async {
        if (!nube.configurada || nube.sincronizando) return;
        // El arranque se anota: si nunca aparece el final, se sabe que
        // empezó (el 26-oct no quedó ni una línea de la de las 02:10).
        bitacora.anotar(Origen.sistema, 'Sincronizar solo, $cuando: empieza.');
        try {
          final dir = await getTemporaryDirectory();
          final r = await nube.sincronizar(
            base: base,
            ruta: ruta,
            carpeta: dir.path,
          );
          reintento.resultado(salioBien: r.falla == null);
          bitacora.anotar(
            Origen.sistema,
            'Sincronizar solo, $cuando: '
            '${textoDeSincronizado(r).replaceAll('\n', ' ')}',
          );
        } catch (e) {
          reintento.resultado(salioBien: false);
          bitacora.anotar(
            Origen.sistema,
            'Sincronizar solo, $cuando, falló en «${nube.ultimoPaso}»: $e',
          );
        }
      }

      // El modo que entregó la última vez va primero: sin esto, en un teléfono
      // donde `normal` no anda, cada viaje empieza perdiendo noventa segundos
      // para volver a descubrir lo mismo.
      final recordado = ModoRecordado(base);
      final cascada = FuenteEnCascada(
        satelites: satelites,
        alEntregar: recordado.recordar,
        // Una FUNCIÓN y no el orden ya calculado: así la cascada vuelve a
        // preguntar al empezar cada viaje. Antes se calculaba una sola vez
        // acá, y lo que se aprendía a mitad de sesión no se usaba hasta
        // reiniciar la aplicación — el primer viaje real lo dejó medido el
        // 2026-09-20, pagando los noventa segundos dos veces seguidas.
        modoPreferido: () => recordado.modo,
      );
      // sitd-57 (general:C4): el viaje, a la Pizarra de este teléfono, que lo
      // manda sin datos a la Pizarra cerca. Sin Pizarra, no hace nada.
      final enlace = EnlaceConPizarra();
      final servicio = ServicioOdometria(
        registro: registro,
        fuente: cascada,
        // Cada viaje que termina entra a la cola. Si no hay señal, espera: la
        // camioneta anda por lugares sin antena y eso no puede perder un viaje.
        alTerminar: (viaje) {
          cola.encolar(viaje);
          anotarEncolado(viaje);
          // sitd-55: si una línea que se repite se salió en este viaje, la
          // próxima vez que se ande a esa velocidad se graban 10 s.
          final linea = marcarParaGrabar(vibraciones, grabaciones, viaje);
          // sitd-57: y lo cuenta a la Pizarra cerca. Sin coordenadas.
          final v = registro.porId(viaje);
          if (v != null) {
            unawaited(
              enlace.enviar(
                eventoTermino(
                  km: v.kilometros,
                  ms: v.duracionMs(DateTime.now().millisecondsSinceEpoch),
                ),
              ),
            );
          }
          if (linea != null) unawaited(enlace.enviar(eventoLinea(linea)));
          // sitd-50: y sincroniza solo. Si no hay señal, queda en la cola y
          // se reintenta al abrir.
          unawaited(sincronizarSolo('al cerrar un viaje'));
        },
      );

      nube = ServicioNube(
        cola: cola,
        guarda: GuardaDeCredencial(base),
        subida: Subida(),
        // Desde `sitd-19`: la contraseña se usa UNA vez, se guarda el
        // `refreshToken` que devuelve el login y se borra. Lo que queda en el
        // teléfono deja de ser la cuenta entera, y se revoca desde la consola
        // sin tocar la contraseña. Ver `GuardaDeSesion`.
        sesion: GuardaDeSesion(base),
        // Desde `sitd-26`: con esto el servicio puede subir el RECORRIDO,
        // que es lo único que sale del teléfono cuando alguien lo pide a
        // mano. Sin esto todo lo demás anda igual y el recorrido no sube.
        viajes: registro,
        // sitd-46: las calibraciones del garage suben solas, cada una en su
        // documento, sin esperar al próximo viaje.
        calibraciones: RegistroDeCalibraciones(base),
        grabaciones: grabaciones,
        // Un documento POR VIAJE y no el reporte entero: así cada documento
        // queda chico —bien abajo del límite de 1 MB de Firestore— y la
        // colección acumulada ES la historia.
        armar: (viaje) => armarReporte(
          base: base,
          viajes: registro,
          cargas: cargas,
          vibraciones: vibraciones,
          audios: audios,
          // Clavado, no elegible. Ver `alcanceQueSeSube`: lo que sale del
          // teléfono es el reporte SIN coordenadas y nada más.
          alcance: alcanceQueSeSube,
          sello: selloApp,
          ahora: DateTime.now().millisecondsSinceEpoch,
          eventos: eventos,
          // Lo último que leyó la escucha de fondo. Sin esto el reporte que
          // sube solo decía «sin arrancar» en todos los teléfonos (`sitd-36`).
          satelites: satelites.ultimo,
          // ESE viaje, no el último. Sin esto, con tres encolados los tres
          // documentos llevarían los datos del más nuevo.
          soloElViaje: viaje,
        ),
      );
      final microfono = MicrofonoDelTelefono();
      // Al abrir se SINCRONIZA solo (sitd-50; antes, sólo lo pendiente). No
      // se espera el resultado: si no hay señal, la aplicación abre igual y
      // se reintenta después. Con un viaje a medio medir que se va a retomar,
      // sólo lo pendiente: la copia entera esperará a que el viaje cierre.
      if (registro.abierto == null) {
        unawaited(sincronizarSolo('al abrir'));
      } else {
        unawaited(nube.subirPendientes());
      }
      // sitd-55: y cuando vuelve la señal. Cada minuto se mira si toca (una
      // falla, o viajes en la cola) y si hay red; con un viaje midiendo, sólo
      // lo pendiente, como al abrir.
      var reintentando = false;
      Timer.periodic(Reintento.cadaCuanto, (_) async {
        if (reintentando || !nube.configurada) return;
        if (!reintento.toca(
          enCola: cola.cuantosFaltan,
          corriendo: nube.sincronizando,
        )) {
          return;
        }
        reintentando = true;
        try {
          if (!await hayRed()) return;
          if (registro.abierto == null) {
            await sincronizarSolo('al volver la señal');
          } else {
            final t = await nube.subirPendientes();
            reintento.resultado(salioBien: t.fallaron == 0);
          }
        } catch (_) {
          reintento.resultado(salioBien: false);
        } finally {
          reintentando = false;
        }
      });
      // Si el sistema mató la aplicación en medio de un viaje, acá se retoma.
      servicio.retomarPendiente();
      // sitd-55: la marcha OÍDA mide las líneas del motor en la vibración, y
      // el acelerómetro crudo va con cada grabación. Se arman acá porque se
      // necesitan entre ellos.
      late final ServicioAudio audio;
      final vibracion = ServicioVibracion(
        registro: vibraciones,
        fuente: Acelerometro(),
        // `sitd-42`: curvas y posición del teléfono. El Redmi 15 no tiene
        // giróscopo; ahí el stream no emite y la vibración sigue igual.
        giroscopo: Giroscopo(),
        velocidadKmh: () => servicio.estado.value.velocidadKmh,
        marcha: () => audio.tacometro
            .leer(
              DateTime.now().millisecondsSinceEpoch,
              servicio.estado.value.velocidadKmh,
            )
            ?.marcha,
      );
      final grabador = Grabador(
        registro: grabaciones,
        acelerometro: vibracion.crudo,
      );
      audio = ServicioAudio(
        registro: audios,
        abrir: microfono.trozos,
        ocupado: microfono.ocupado,
        velocidadKmh: () => servicio.estado.value.velocidadKmh,
        grabador: grabador,
      );
      // sitd-57: cada 2 s, mientras se mide, el viaje en vivo a la Pizarra; y
      // cuando empieza uno, un aviso. El viaje que ya estaba abierto al abrir
      // la aplicación (retomado) no se anuncia como nuevo.
      int? viajeAnunciado = servicio.estado.value.viaje;
      Timer.periodic(const Duration(seconds: 2), (_) {
        try {
          final e = servicio.estado.value;
          if (!e.midiendo || e.viaje == null) return;
          if (e.viaje != viajeAnunciado) {
            viajeAnunciado = e.viaje;
            unawaited(enlace.enviar(eventoEmpezo()));
          }
          final t = DateTime.now().millisecondsSinceEpoch;
          final kmh = e.velocidadKmh;
          final oido = audio.tacometro.leer(t, kmh);
          unawaited(
            enlace.enviar(
              mensajeVivo(
                kmh: kmh,
                km: e.kilometros,
                rpm: oido?.rpm,
                marcha: oido?.marcha,
              ),
            ),
          );
        } catch (_) {
          // El enlace describe, no mide: nunca puede trabar un viaje.
        }
      });
      return Arranque._(
        ruta: ruta,
        base: base,
        registro: registro,
        cargas: cargas,
        vibraciones: vibraciones,
        despierta: PantallaDespierta(base),
        servicio: servicio,
        gps: cascada,
        eventos: eventos,
        satelites: satelites,
        modoRecordado: recordado,
        cola: cola,
        nube: nube,
        // La velocidad sale del servicio de odometría y no de una segunda
        // suscripción al GPS: el receptor se le pide una sola vez al teléfono.
        vibracion: vibracion,
        audios: audios,
        // Lo mismo para el micrófono: la velocidad sale de la odometría.
        audio: audio,
        grabador: grabador,
        cargador: CargadorDelTelefono().avisos(),
      );
    } catch (e) {
      bitacora.anotar(Origen.sistema, 'La base NO abrió: $e');
      return Arranque._(ruta: ruta, error: '$e');
    }
  }
}

/// Al cerrar un viaje (`sitd-55`): si alguna línea que se repite se salió de
/// lo normal en ESTE viaje, se pide una grabación para la próxima vez que se
/// ande a esa velocidad. Para grabar alcanza con un viaje —es juntar
/// evidencia—; para AVISAR siguen haciendo falta tres seguidos. Nunca tira:
/// esto no puede impedir que un viaje se cierre. Devuelve el texto de la
/// línea más salida, para contárselo a la Pizarra cerca (`sitd-57`), o `null`.
String? marcarParaGrabar(
  RegistroDeVibracion vibraciones,
  RegistroDeGrabaciones grabaciones,
  int viaje,
) {
  try {
    final porViaje = deLaClaseVigente(vibraciones.porViaje());
    final base = baseDeLineas(porViaje, excepto: {viaje});
    final desvios = compararLineas(porViaje[viaje] ?? const [], base);
    if (desvios.isEmpty) return null;
    for (final d in desvios.take(3)) {
      bitacora.anotar(Origen.sistema, 'Línea fuera de lo normal: ${d.texto}');
    }
    final d = desvios.first;
    if (grabaciones.pendiente == null) {
      grabaciones.pedir(
        PedidoDeGrabar(
          motivoDeLinea(d.linea.clave, d.cubeta, d.que.name),
          cubeta: d.cubeta,
        ),
      );
    }
    return d.texto;
  } catch (e) {
    bitacora.anotar(Origen.sistema, 'No se pudieron revisar las líneas: $e');
    return null;
  }
}
