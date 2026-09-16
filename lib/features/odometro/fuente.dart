import 'muestra.dart';

/// Lo que entrega una fuente en cada entrega del receptor.
///
/// Una lectura **sin** [muestra] no es un error ni algo que se pueda ignorar:
/// es una posición que llegó sin velocidad Doppler, y ésa es la trampa que
/// arruina la odometría en silencio. Android entrega `speed == 0.0` cuando no
/// tiene el dato, no un nulo, así que copiarlo tal cual haría que un receptor
/// que todavía no fijó satélites se leyera como una camioneta detenida. Se
/// cuentan aparte y se muestran: un viaje que no avanza tiene que poder
/// distinguirse de una camioneta que no se movió.
class Lectura {
  final Muestra? muestra;

  /// La precisión que traía la posición **cuando no se pudo usar**, o `null`.
  ///
  /// **Es lo único que distingue dos problemas muy distintos**, y hasta
  /// `sitd-12` se perdía: una posición sin velocidad con cuatrocientos metros
  /// de error es ubicación de red —wifi y torres de celular, que nunca traen
  /// velocidad—, y una con ocho metros es un satélite que todavía no resolvió
  /// la velocidad. La primera no se arregla esperando; la segunda sí.
  final double? precisionCruda;

  const Lectura(this.muestra, {this.precisionCruda});

  bool get sinDoppler => muestra == null;
}

/// Por qué el GPS entra por una interfaz y no directo del complemento.
///
/// Es la misma decisión que `FuenteDeRegimen` para el OBD2: el motor de
/// odometría no tiene que saber de dónde salen las muestras. Con eso, el banco
/// de pruebas ejercita el circuito entero —permiso, viaje abierto, puntos
/// guardados, kilómetros en pantalla— sin GPS, sin teléfono y sin emulador,
/// que es la única forma de probarlo en cada tanda y no una vez por mes arriba
/// de la camioneta.
///
/// Y deja abierta la puerta que va a hacer falta igual: una fuente que lea un
/// recorrido guardado y lo reproduzca, para depurar un viaje real sin salir a
/// manejarlo de nuevo.
abstract class FuenteDeMuestras {
  /// Las lecturas, a medida que llegan. Puede tardar decenas de segundos en
  /// emitir la primera: el receptor necesita ver cielo y fijar satélites.
  ///
  /// **Es un solo stream y se escucha una sola vez.** Abrir dos suscripciones
  /// contra el GPS del teléfono es pedirle dos veces lo mismo al receptor y
  /// pagarlo en batería, así que lo que no sirve viaja por acá adentro en vez
  /// de por un canal aparte.
  Stream<Lectura> get lecturas;

  /// Pide lo que haga falta —permiso, servicio de ubicación encendido— y dice
  /// si se puede arrancar. **No lanza**: devuelve el motivo, que es lo que hay
  /// que mostrarle a quien está mirando la pantalla.
  Future<Disponibilidad> preparar();

  /// Corta la entrega de muestras y suelta lo que haya que soltar.
  Future<void> detener();
}

/// Por qué no se puede arrancar, cuando no se puede.
enum MotivoGps {
  /// Se puede arrancar.
  listo,

  /// El sistema tiene la ubicación apagada, para todas las aplicaciones.
  ubicacionApagada,

  /// Falta el permiso y todavía se puede pedir.
  sinPermiso,

  /// El permiso está negado de forma permanente: desde la aplicación no se
  /// puede volver a pedir, hay que ir a los ajustes del sistema.
  permisoNegadoParaSiempre,

  /// Cualquier otra cosa. El detalle viene aparte.
  falla,
}

/// El resultado de [FuenteDeMuestras.preparar], con el texto que va a leer una
/// persona.
///
/// El mensaje dice **la causa y qué hacer**, no un código: un error sin causa
/// es un problema de dos minutos convertido en tres días
/// (`PROTOCOLO-INTERFAZ.md` § 7.2).
class Disponibilidad {
  final MotivoGps motivo;

  /// Lo que dijo el sistema, cuando dijo algo. Se muestra debajo del mensaje.
  final String? detalle;

  const Disponibilidad(this.motivo, {this.detalle});

  static const Disponibilidad listo = Disponibilidad(MotivoGps.listo);

  bool get puedeArrancar => motivo == MotivoGps.listo;

  String get mensaje => switch (motivo) {
    MotivoGps.listo => 'El GPS está listo.',
    MotivoGps.ubicacionApagada =>
      'La ubicación del teléfono está apagada. Se prende en los ajustes '
          'rápidos, con el mismo interruptor que usa el mapa.',
    MotivoGps.sinPermiso =>
      'Falta darle permiso de ubicación a la aplicación. Sin eso no hay '
          'kilómetros: es de donde sale la velocidad.',
    MotivoGps.permisoNegadoParaSiempre =>
      'El permiso de ubicación quedó negado para siempre, así que desde acá '
          'no se puede volver a pedir. Se cambia en Ajustes → Aplicaciones → '
          'SITD Hilux → Permisos → Ubicación.',
    MotivoGps.falla => 'El GPS no arrancó.',
  };
}
