import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/combustible/registro_cargas.dart';
import '../features/odometro/cascada.dart';
import '../features/odometro/modo_recordado.dart';
import '../features/odometro/pantalla_despierta.dart';
import '../features/vibracion/fuente_vibracion.dart';
import '../features/vibracion/registro_vibracion.dart';
import '../features/vibracion/servicio_vibracion.dart';
import '../features/nube/cola.dart';
import '../features/nube/credencial.dart';
import '../features/nube/servicio_nube.dart';
import '../features/nube/sesion.dart';
import '../features/nube/subida.dart';
import '../features/odometro/registro.dart';
import '../features/respaldo/reporte.dart';
import 'version.dart';
import '../features/sensores/satelites.dart';
import '../features/odometro/servicio.dart';
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
    this.gps,
    this.eventos,
    this.satelites,
    this.modoRecordado,
    this.cola,
    this.nube,
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
      final satelites = Satelites();
      // No se espera: si el canal tarda o no está, la aplicación abre igual.
      unawaited(satelites.arrancar());
      final registro = RegistroDeViajes(base);
      final cargas = RegistroDeCargas(base);
      final vibraciones = RegistroDeVibracion(base);
      final cola = ColaDeSubida(base);
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
      final servicio = ServicioOdometria(
        registro: registro,
        fuente: cascada,
        // Cada viaje que termina entra a la cola. Si no hay señal, espera: la
        // camioneta anda por lugares sin antena y eso no puede perder un viaje.
        alTerminar: (viaje) {
          cola.encolar(viaje);
          anotarEncolado(viaje);
        },
      );

      final nube = ServicioNube(
        cola: cola,
        guarda: GuardaDeCredencial(base),
        subida: Subida(),
        // Desde `sitd-19`: la contraseña se usa UNA vez, se guarda el
        // `refreshToken` que devuelve el login y se borra. Lo que queda en el
        // teléfono deja de ser la cuenta entera, y se revoca desde la consola
        // sin tocar la contraseña. Ver `GuardaDeSesion`.
        sesion: GuardaDeSesion(base),
        // Un documento POR VIAJE y no el reporte entero: así cada documento
        // queda chico —bien abajo del límite de 1 MB de Firestore— y la
        // colección acumulada ES la historia.
        armar: (viaje) => armarReporte(
          base: base,
          viajes: registro,
          cargas: cargas,
          vibraciones: vibraciones,
          // Clavado, no elegible. Ver `alcanceQueSeSube`: lo que sale del
          // teléfono es el reporte SIN coordenadas y nada más.
          alcance: alcanceQueSeSube,
          sello: selloApp,
          ahora: DateTime.now().millisecondsSinceEpoch,
          eventos: eventos,
          // ESE viaje, no el último. Sin esto, con tres encolados los tres
          // documentos llevarían los datos del más nuevo.
          soloElViaje: viaje,
        ),
      );
      // Al abrir se intenta lo que quedó esperando. No se espera el resultado:
      // si no hay señal, la aplicación abre igual y se reintenta después.
      unawaited(nube.subirPendientes());
      // Si el sistema mató la aplicación en medio de un viaje, acá se retoma.
      servicio.retomarPendiente();
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
        vibracion: ServicioVibracion(
          registro: vibraciones,
          fuente: Acelerometro(),
          velocidadKmh: () => servicio.estado.value.velocidadKmh,
        ),
      );
    } catch (e) {
      bitacora.anotar(Origen.sistema, 'La base NO abrió: $e');
      return Arranque._(ruta: ruta, error: '$e');
    }
  }
}
