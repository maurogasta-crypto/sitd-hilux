import 'package:geolocator/geolocator.dart';

import 'fuente.dart';
import 'muestra.dart';

/// Traduce una posición de Android a una [Muestra] del proyecto.
///
/// **Devuelve `null` cuando la posición no trae velocidad Doppler, y ésa es la
/// trampa que este archivo existe para evitar.** Android entrega `speed == 0.0`
/// cuando no tiene el dato, no un nulo: si se copiara tal cual, un receptor sin
/// fijar satélites parecería una camioneta detenida, la integración daría cero
/// y el viaje saldría con menos kilómetros de los que hizo — sin un solo error
/// en pantalla. Por eso se mira `hasSpeed` y no `speed`.
///
/// Lo mismo con la precisión: sin ella no hay forma de descartar una muestra
/// mala, así que tampoco entra.
Muestra? muestraDePosicion(Position p) {
  if (!p.hasSpeed || !p.hasAccuracy) return null;
  return Muestra(
    t: p.timestamp.millisecondsSinceEpoch,
    lat: p.latitude,
    lon: p.longitude,
    alt: p.hasAltitude ? p.altitude : null,
    velocidad: p.speed,
    precision: p.accuracy,
    precisionVel: p.hasSpeedAccuracy ? p.speedAccuracy : null,
  );
}

/// El GPS del teléfono, con el servicio en primer plano puesto.
///
/// **Lo que este servicio sí hace y lo que no.** La notificación persistente
/// sube la prioridad del proceso y le dice al sistema —y a quien mira el
/// teléfono— que la aplicación está midiendo; con eso el GPS sigue entregando
/// con la pantalla apagada. Lo que NO hace es sobrevivir a que el sistema mate
/// la actividad: el complemento lo dice con todas las letras en su
/// documentación, y MIUI lo hace igual si no se le desactivan las
/// restricciones a mano. Por eso hay dos redes abajo: cada punto se guarda
/// apenas llega, y al volver a abrir se retoma el viaje que quedó sin cerrar.
///
/// Si con eso todavía se pierden viajes, lo que sigue es un motor de Flutter
/// aparte en un servicio propio —que es un cambio grande— y no un ajuste acá.
/// Las tres formas de pedirle posiciones a Android.
///
/// **Existen porque el 2026-09-16 el receptor no entregó NI UNA a cielo
/// abierto, dos veces.** Con cero lecturas —ni siquiera descartadas— el
/// problema está antes del filtro: o del permiso, o de cómo se le pide. Cada
/// modo saca una pieza del medio, y probándolos en la cabina se ve cuál es.
enum ModoGps {
  /// Como mide un viaje: servicio en primer plano con notificación, y el
  /// proveedor fusionado de Google.
  normal,

  /// Igual, pero **sin** el servicio en primer plano. Si con esto entra y con
  /// el normal no, el que falla es el servicio — y eso en un Xiaomi es
  /// creíble: HyperOS bloquea servicios en primer plano con la mano suelta.
  sinNotificacion,

  /// El **LocationManager** de Android en vez del proveedor fusionado de
  /// Google. Salta Play Services entero. Si sólo con esto entra, el problema
  /// está ahí y no en la aplicación.
  receptorDirecto,
}

String nombreDeModo(ModoGps m) => switch (m) {
  ModoGps.normal => 'Normal',
  ModoGps.sinNotificacion => 'Sin notificación',
  ModoGps.receptorDirecto => 'Receptor directo',
};

/// Lo que se sabe del GPS sin haber recibido todavía una posición.
class DiagnosticoGps {
  /// `whileInUse`, `always`, `denied`, `deniedForever`…
  final String permiso;

  /// Si la ubicación del sistema está encendida.
  final bool servicioEncendido;

  /// La última posición que el SISTEMA conoce, de cualquier aplicación.
  ///
  /// **Es la pregunta que separa dos mundos.** Si hay una última conocida
  /// razonable, el receptor del teléfono funciona y el problema es de cómo la
  /// pide esta aplicación. Si no hay ninguna, el receptor no fijó nunca —y eso
  /// no lo arregla ningún código.
  final Muestra? ultimaConocida;

  final String? falla;

  const DiagnosticoGps({
    required this.permiso,
    required this.servicioEncendido,
    this.ultimaConocida,
    this.falla,
  });
}

class FuenteGps implements FuenteDeMuestras {
  /// Cada cuánto se pide una posición. A 1 Hz la regla del trapecio ya no
  /// aporta error frente al propio sensor, y el gasto de batería es el que
  /// tiene cualquier navegador andando.
  final Duration intervalo;

  /// Cómo se le pide al sistema. Un viaje usa [ModoGps.normal]; los otros dos
  /// son para la pantalla de sensores, que es donde se diagnostica.
  final ModoGps modo;

  /// Sólo para el banco de pruebas: deja poner un GPS de mentira en lugar del
  /// del teléfono.
  final GeolocatorPlatform gps;

  FuenteGps({
    this.intervalo = const Duration(seconds: 1),
    this.modo = ModoGps.normal,
    GeolocatorPlatform? gps,
  }) : gps = gps ?? GeolocatorPlatform.instance;

  /// Todo lo que se puede saber antes de la primera posición.
  Future<DiagnosticoGps> diagnosticar() async {
    var permiso = 'sin averiguar';
    var encendido = false;
    try {
      encendido = await gps.isLocationServiceEnabled();
      permiso = (await gps.checkPermission()).name;
      final ultima = await gps.getLastKnownPosition();
      return DiagnosticoGps(
        permiso: permiso,
        servicioEncendido: encendido,
        ultimaConocida: ultima == null ? null : muestraDePosicion(ultima),
      );
    } catch (e) {
      return DiagnosticoGps(
        permiso: permiso,
        servicioEncendido: encendido,
        falla: '$e',
      );
    }
  }

  @override
  Stream<Lectura> get lecturas => gps
      .getPositionStream(locationSettings: _ajustes)
      .map((p) => Lectura(muestraDePosicion(p)));

  /// Los mismos ajustes que usa el stream, para que el banco pueda mirarlos.
  /// Sin esto, la diferencia entre los tres modos sólo se podría comprobar
  /// arriba de la camioneta.
  LocationSettings get ajustesParaPruebas => _ajustes;

  LocationSettings get _ajustes => AndroidSettings(
    accuracy: LocationAccuracy.best,
    // Sin filtro de distancia: la integración necesita muestras a intervalos
    // parejos. Con filtro, el receptor calla mientras el vehículo está quieto
    // y el hueco resultante se lee como un corte.
    distanceFilter: 0,
    intervalDuration: intervalo,
    forceLocationManager: modo == ModoGps.receptorDirecto,
    foregroundNotificationConfig: modo == ModoGps.normal
        ? const ForegroundNotificationConfig(
            notificationTitle: 'SITD Hilux',
            notificationText: 'Midiendo el viaje',
            notificationChannelName: 'Odometría',
            setOngoing: true,
            enableWakeLock: true,
          )
        : null,
  );

  @override
  Future<Disponibilidad> preparar() async {
    try {
      if (!await gps.isLocationServiceEnabled()) {
        return const Disponibilidad(MotivoGps.ubicacionApagada);
      }
      var permiso = await gps.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await gps.requestPermission();
      }
      return switch (permiso) {
        LocationPermission.always ||
        LocationPermission.whileInUse => Disponibilidad.listo,
        LocationPermission.deniedForever => const Disponibilidad(
          MotivoGps.permisoNegadoParaSiempre,
        ),
        _ => const Disponibilidad(MotivoGps.sinPermiso),
      };
    } catch (e) {
      return Disponibilidad(MotivoGps.falla, detalle: '$e');
    }
  }

  @override
  Future<void> detener() async {
    // El stream se cierra del lado del que escucha: cancelar la suscripción es
    // lo que apaga el servicio en primer plano. Acá no queda nada colgado.
  }
}
