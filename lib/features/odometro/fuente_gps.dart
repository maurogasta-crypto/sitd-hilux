import 'package:geolocator/geolocator.dart';

import '../../core/bitacora.dart';
import 'fuente.dart';
import 'muestra.dart';

/// Qué trae de verdad una posición: si informó velocidad, y si informó
/// precisión.
///
/// ## Por qué esto no puede preguntarle a `hasSpeed` y `hasAccuracy`
///
/// **Porque en Android esas dos banderas valen `false` SIEMPRE, y es un error
/// del paquete, no del teléfono.** Está en `geolocator_android` 5.0.3 —la
/// última publicada al 2026-09-17— en `AndroidPosition.fromMap`: llama a
/// `Position.fromMap`, que calcula bien las banderas mirando qué claves mandó
/// el lado nativo, y después construye un `AndroidPosition` copiando **sólo
/// los números**. El constructor ni siquiera acepta las banderas, así que
/// caen a su valor por defecto, que es `false`.
///
/// El banco lo reproduce en `fuente_gps_test.dart`: una posición con 7,5 m de
/// precisión, 12,3 m/s de velocidad y 0,4 de margen vuelve con `hasAccuracy`
/// y `hasSpeed` en `false`.
///
/// **Lo que costó:** este proyecto descartaba el 100 % de las posiciones del
/// GPS en Android, en cualquier teléfono, desde siempre. Tres días buscándolo
/// en el receptor, en los permisos, en HyperOS y en el servicio en primer
/// plano. Dos viajes reales —68 y 162 posiciones— terminaron en cero metros
/// con el receptor funcionando perfectamente.
///
/// ## Cómo se deduce sin las banderas, y qué se pierde
///
/// El lado nativo **omite la clave** cuando el sensor no midió el valor, y el
/// lado de Dart pone `0.0` en su lugar. Entonces:
///
/// - **precisión**: `accuracy > 0` la tuvo. Una precisión de exactamente cero
///   metros no existe en un receptor real, así que el cero sólo puede ser la
///   clave ausente.
/// - **velocidad**: `speed > 0` **o** `speedAccuracy > 0`. El segundo es el que
///   importa: una camioneta DETENIDA informa `speed` en cero legítimamente, y
///   sin esto se la descartaría. Android sólo informa el margen de error de la
///   velocidad cuando tiene velocidad, así que un margen mayor que cero prueba
///   que el cero es real y no una ausencia.
///
/// **Lo que se pierde, dicho sin maquillaje:** en un teléfono que no informe
/// `speedAccuracy` (existe desde la API 26, y los dos de este proyecto la
/// superan), una camioneta detenida se descarta. Es el lado correcto para
/// equivocarse — sigue valiendo la regla de que una velocidad cero sin
/// respaldo no es una camioneta quieta— y cuando arranque, entra sola.

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
({bool velocidad, bool precision}) loQueTrae(Position p) => (
  // Se respeta la bandera cuando dice que SÍ —en iOS funciona, y si el
  // paquete se arregla esto sigue andando sin tocar nada— y sólo se deduce
  // cuando dice que no.
  velocidad: p.hasSpeed || p.speed > 0 || p.speedAccuracy > 0,
  precision: p.hasAccuracy || p.accuracy > 0,
);

Muestra? muestraDePosicion(Position p) {
  final trae = loQueTrae(p);
  if (!trae.velocidad || !trae.precision) return null;
  return Muestra(
    t: p.timestamp.millisecondsSinceEpoch,
    lat: p.latitude,
    lon: p.longitude,
    // Misma trampa que arriba: la bandera no sirve, el cero es la ausencia.
    alt: p.altitude != 0 ? p.altitude : null,
    velocidad: p.speed,
    precision: p.accuracy,
    precisionVel: p.speedAccuracy > 0 ? p.speedAccuracy : null,
  );
}

/// Escribe en la bitácora QUÉ trae una posición que llegó sin velocidad.
///
/// **Es la línea que faltaba, y el reporte del 2026-09-16 lo dejó a la vista.**
/// Ese viaje registró 68 posiciones con `sinDoppler` y ni una usada: o sea que
/// el receptor NO estaba callado —llegaba una cada 2,3 segundos— pero ninguna
/// traía velocidad. Y con un contador pelado eso no se puede diagnosticar: 68
/// posiciones de ubicación de red (wifi y torres de celular, que nunca traen
/// velocidad, con cientos de metros de error) y 68 posiciones de un GNSS que
/// todavía no resolvió la velocidad son problemas distintos y se veían igual.
///
/// La precisión los separa de un vistazo: arriba de cien metros es red, abajo
/// de veinte es satélite. Se anota **sólo cuando cambia de tramo**, no una vez
/// por segundo: lo que importa es de qué clase son, no el latido.
void anotarSinDoppler(Position p) {
  final trae = loQueTrae(p);
  final precision = trae.precision ? p.accuracy : double.nan;
  final tramo = precision.isNaN
      ? 'sin precisión declarada'
      : precision > 100
      ? 'con MUCHO error (${precision.toStringAsFixed(0)} m): eso es '
            'ubicación de red —wifi y torres—, no satélite'
      : precision > 20
      ? 'con ${precision.toStringAsFixed(0)} m de error: zona gris entre red '
            'y satélite'
      : 'con sólo ${precision.toStringAsFixed(0)} m de error: es satélite, '
            'pero sin resolver la velocidad todavía';
  bitacora.anotarSiCambio(
    Origen.gps,
    'Llegan posiciones SIN velocidad Doppler, $tramo'
    '${p.isMocked ? " — y son SIMULADAS: hay una aplicación de ubicación falsa activa" : ""}.',
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
      if (ultima != null && ultima.isMocked) {
        bitacora.anotar(
          Origen.gps,
          'OJO: la última posición conocida está marcada como SIMULADA. Hay '
          'una aplicación de ubicación falsa activa en el teléfono.',
        );
      }
      bitacora.anotar(
        Origen.gps,
        'Diagnóstico: permiso $permiso · ubicación del sistema '
        '${encendido ? "encendida" : "APAGADA"} · última posición conocida '
        'del sistema: ${ultima == null ? "NO HAY NINGUNA" : "sí hay"}.',
      );
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
  Stream<Lectura> get lecturas =>
      gps.getPositionStream(locationSettings: _ajustes).map((p) {
        final m = muestraDePosicion(p);
        if (m != null) return Lectura(m);
        anotarSinDoppler(p);
        return Lectura(null, precisionCruda: p.hasAccuracy ? p.accuracy : null);
      });

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
      bitacora.anotar(Origen.permiso, 'Permiso de ubicación: ${permiso.name}.');
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
