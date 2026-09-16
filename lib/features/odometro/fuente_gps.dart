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
class FuenteGps implements FuenteDeMuestras {
  /// Cada cuánto se pide una posición. A 1 Hz la regla del trapecio ya no
  /// aporta error frente al propio sensor, y el gasto de batería es el que
  /// tiene cualquier navegador andando.
  final Duration intervalo;

  /// Sólo para el banco de pruebas: deja poner un GPS de mentira en lugar del
  /// del teléfono.
  final GeolocatorPlatform gps;

  FuenteGps({
    this.intervalo = const Duration(seconds: 1),
    GeolocatorPlatform? gps,
  }) : gps = gps ?? GeolocatorPlatform.instance;

  @override
  Stream<Lectura> get lecturas => gps
      .getPositionStream(locationSettings: _ajustes)
      .map((p) => Lectura(muestraDePosicion(p)));

  LocationSettings get _ajustes => AndroidSettings(
    accuracy: LocationAccuracy.best,
    // Sin filtro de distancia: la integración necesita muestras a intervalos
    // parejos. Con filtro, el receptor calla mientras el vehículo está quieto
    // y el hueco resultante se lee como un corte.
    distanceFilter: 0,
    intervalDuration: intervalo,
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'SITD Hilux',
      notificationText: 'Midiendo el viaje',
      notificationChannelName: 'Odometría',
      setOngoing: true,
      enableWakeLock: true,
    ),
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
