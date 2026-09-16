import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/combustible/registro_cargas.dart';
import '../features/odometro/fuente_gps.dart';
import '../features/odometro/pantalla_despierta.dart';
import '../features/vibracion/fuente_vibracion.dart';
import '../features/vibracion/registro_vibracion.dart';
import '../features/vibracion/servicio_vibracion.dart';
import '../features/odometro/registro.dart';
import '../features/odometro/servicio.dart';
import 'db/base.dart';

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
      final registro = RegistroDeViajes(base);
      final servicio = ServicioOdometria(
        registro: registro,
        fuente: FuenteGps(),
      );
      // Si el sistema mató la aplicación en medio de un viaje, acá se retoma.
      servicio.retomarPendiente();
      final vibraciones = RegistroDeVibracion(base);
      return Arranque._(
        ruta: ruta,
        base: base,
        registro: registro,
        cargas: RegistroDeCargas(base),
        vibraciones: vibraciones,
        despierta: PantallaDespierta(base),
        servicio: servicio,
        // La velocidad sale del servicio de odometría y no de una segunda
        // suscripción al GPS: el receptor se le pide una sola vez al teléfono.
        vibracion: ServicioVibracion(
          registro: vibraciones,
          fuente: Acelerometro(),
          velocidadKmh: () => servicio.estado.value.velocidadKmh,
        ),
      );
    } catch (e) {
      return Arranque._(ruta: ruta, error: '$e');
    }
  }
}
