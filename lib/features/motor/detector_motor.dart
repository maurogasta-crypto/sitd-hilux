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
///  4. **Un viaje del cargador está A PRUEBA hasta que la camioneta se mueve**
///     (`sitd-40`, 17-oct-2026). Mauro enchufó el teléfono en un cargador de
///     la CASA y la app abrió un viaje que duró dos horas con cero metros: el
///     cargador dice «hay corriente», no «es la Hilux». Si en [prueba] no se
///     anduvieron [metrosMinimos], o si se apaga antes de andarlos, el viaje
///     se DESCARTA —se borra, no se guarda ni se sube—. Una vez que anduvo,
///     es un viaje como cualquiera.
///  5. **Y también si lo cierra una persona** (`sitd-43`, 18-oct-2026). El
///     viaje 19 del Note 9 lo abrió el cargador, alguien tocó Terminar a los
///     20 segundos con un metro andado, y subió como un viaje más. Mauro:
///     «que se descarte también si se cierra a mano». Cerrar a mano un viaje
///     del cargador que todavía está a prueba lo descarta, igual que si se le
///     acabara el tiempo ([descartaAlCerrarAMano]).
///
/// No sabe nada de Android: recibe los cambios y el reloj, y dice qué hacer.
library;

/// Lo que el detector le pide a la pantalla.
enum AccionMotor { nada, empezar, terminar, descartar }

class DetectorMotor {
  /// Cuánto tiempo sin carga antes de cerrar el viaje que abrió el motor.
  final Duration gracia;

  /// Cuánto tiene la camioneta para moverse antes de descartar el viaje.
  final Duration prueba;

  /// Cuánto hay que andar para que el viaje del cargador sea un viaje.
  final double metrosMinimos;

  DetectorMotor({
    this.gracia = const Duration(minutes: 3),
    this.prueba = const Duration(minutes: 5),
    this.metrosMinimos = 200,
  });

  bool? _conectado;
  int? _sinCargaDesde;
  int? _abiertoT;

  /// Si el viaje que está abierto lo abrió el motor. Lo pone la pantalla
  /// (con [abrioElMotor]) cuando el arranque automático anduvo, y lo saca al
  /// cerrar.
  bool abiertoPorElMotor = false;

  /// Si el viaje del cargador todavía no anduvo lo suficiente.
  bool get aPrueba => abiertoPorElMotor && _abiertoT != null;

  /// Si una persona cierra ahora el viaje, con [metros] andados, ¿se descarta?
  /// Sólo si lo abrió el cargador y no llegó a [metrosMinimos]: un viaje que
  /// abrió una persona, o uno del cargador que ya anduvo, se guarda siempre.
  bool descartaAlCerrarAMano(double metros) =>
      aPrueba && metros < metrosMinimos;

  /// El viaje lo abrió el cargador en [t]: arranca a prueba.
  void abrioElMotor(int t) {
    abiertoPorElMotor = true;
    _abiertoT = t;
  }

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

  /// Se llama cada tanto (la pantalla late una vez por segundo), con lo que
  /// lleva andado el viaje ([metros]).
  AccionMotor alLatir({
    required bool hayViaje,
    required int t,
    double metros = 0,
  }) {
    // La prueba: anduvo lo suficiente → viaje de verdad; se le acabó el
    // tiempo sin andar → se descarta.
    final abierto = _abiertoT;
    if (hayViaje && abiertoPorElMotor && abierto != null) {
      if (metros >= metrosMinimos) {
        _abiertoT = null;
      } else if (t - abierto >= prueba.inMilliseconds) {
        _abiertoT = null;
        _sinCargaDesde = null;
        return AccionMotor.descartar;
      }
    }
    final desde = _sinCargaDesde;
    if (desde == null) return AccionMotor.nada;
    if (!hayViaje || !abiertoPorElMotor) {
      _sinCargaDesde = null;
      return AccionMotor.nada;
    }
    if (t - desde >= gracia.inMilliseconds) {
      _sinCargaDesde = null;
      // Se apagó sin haber andado: tampoco era un viaje.
      if (aPrueba && metros < metrosMinimos) {
        _abiertoT = null;
        return AccionMotor.descartar;
      }
      _abiertoT = null;
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
