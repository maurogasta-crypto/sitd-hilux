/// El viaje empieza y termina con el motor, por el cargador (`sitd-37`).
///
/// Lo pidió Mauro el 2026-10-14 («vamos con el detector de auto encendido»).
/// El cargador del encendedor de la Hilux da corriente sólo con el contacto
/// puesto: que el teléfono pase a cargar quiere decir que arrancó el motor, y
/// que deje de cargar, que lo apagaron. Hasta acá este proyecto decía que el
/// viaje lo abre una persona porque no había con qué distinguir «salió a la
/// ruta» de «la movieron en el taller»; el contacto puesto es esa señal.
///
/// Tres reglas que no se negocian, y el banco las comprueba:
///
///  1. **Sólo un CAMBIO abre un viaje.** Si la aplicación abre con el teléfono
///     ya cargando —en casa, en el escritorio— no se inventa un viaje: hace
///     falta ver el paso de «no carga» a «carga».
///  2. **Sólo cierra lo que abrió.** Un viaje que empezó una persona lo
///     termina una persona; desenchufar el cargador no lo toca.
///  3. **Cerrar espera.** Un corte de contacto de un minuto —una parada, el
///     motor que se apaga en un semáforo— no corta el viaje: hace falta
///     [gracia] sin carga. Si vuelve antes, no pasó nada.
///
/// No sabe nada de Android: recibe los cambios y el reloj, y dice qué hacer.
library;

/// Lo que el detector le pide a la pantalla.
enum AccionMotor { nada, empezar, terminar }

class DetectorMotor {
  /// Cuánto tiempo sin carga antes de cerrar el viaje que abrió el motor.
  final Duration gracia;

  DetectorMotor({this.gracia = const Duration(minutes: 3)});

  bool? _conectado;
  int? _sinCargaDesde;

  /// Si el viaje que está abierto lo abrió el motor. Lo pone la pantalla
  /// cuando el arranque automático anduvo, y lo saca al cerrar.
  bool abiertoPorElMotor = false;

  bool? get cargando => _conectado;

  /// Un aviso del cargador. [inicial] es el primero, el que dice cómo estaba
  /// al abrir: ése sólo se anota, nunca abre nada.
  AccionMotor alCambiar({
    required bool conectado,
    required bool inicial,
    required bool hayViaje,
    required int t,
  }) {
    final antes = _conectado;
    _conectado = conectado;
    if (inicial || antes == null) {
      _sinCargaDesde = conectado ? null : _sinCargaDesde;
      return AccionMotor.nada;
    }
    if (antes == conectado) return AccionMotor.nada;
    if (conectado) {
      _sinCargaDesde = null;
      return hayViaje ? AccionMotor.nada : AccionMotor.empezar;
    }
    if (hayViaje && abiertoPorElMotor) _sinCargaDesde = t;
    return AccionMotor.nada;
  }

  /// Se llama cada tanto (la pantalla late una vez por segundo).
  AccionMotor alLatir({required bool hayViaje, required int t}) {
    final desde = _sinCargaDesde;
    if (desde == null) return AccionMotor.nada;
    if (!hayViaje || !abiertoPorElMotor) {
      _sinCargaDesde = null;
      return AccionMotor.nada;
    }
    if (t - desde >= gracia.inMilliseconds) {
      _sinCargaDesde = null;
      return AccionMotor.terminar;
    }
    return AccionMotor.nada;
  }

  /// Cuántos segundos faltan para cerrar, para mostrarlo; `null` si no hay
  /// cierre pendiente.
  int? segundosParaCerrar(int t) {
    final desde = _sinCargaDesde;
    if (desde == null) return null;
    final faltan = gracia.inMilliseconds - (t - desde);
    return faltan <= 0 ? 0 : (faltan / 1000).ceil();
  }
}
