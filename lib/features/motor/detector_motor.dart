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
///  1. **Abrir la app con el teléfono YA cargando también abre un viaje**
///     (`sitd-56`, 26-oct-2026, Mauro: «la propia apk, al estar conectada e
///     iniciada en el dispositivo que va a funcionar como detector, debería
///     funcionar automáticamente los recorridos para que siga habiendo un
///     registro»). Hasta `sitd-55` hacía falta ver el paso de «no carga» a
///     «carga», para no inventar un viaje en el escritorio de la casa; desde
///     `sitd-40` ese viaje queda A PRUEBA y se borra solo si no anda (regla
///     4), así que la red ya está. El 26-oct el Note 9 se abrió a las 02:10
///     con el motor en marcha y el viaje hubo que empezarlo a mano.
///  2. **Sólo cierra lo que abrió.** Un viaje que empezó una persona lo
///     termina una persona; desenchufar el cargador no lo toca.
///  3. **Cerrar espera, y espera QUIETO.** Un corte de contacto de un minuto
///     —una parada, el motor que se apaga en un semáforo— no corta el viaje:
///     hace falta [gracia] sin carga **y con la camioneta parada**
///     (`sitd-56`). El cargador del encendedor se corta andando: en el viaje
///     23 del Note 9 dejó de cargar 3 min 28 s a mitad de ruta, y con sólo
///     la gracia el viaje se habría partido en dos. Si vuelve la carga, o si
///     la camioneta se mueve, se vuelve a contar.
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
      // Regla 1: la app abrió con el motor en marcha. A prueba, como todos.
      return conectado && !hayViaje ? AccionMotor.empezar : AccionMotor.nada;
    }
    if (antes == conectado) return AccionMotor.nada;
    if (conectado) {
      _sinCargaDesde = null;
      return hayViaje ? AccionMotor.nada : AccionMotor.empezar;
    }
    if (hayViaje && abiertoPorElMotor) _sinCargaDesde = t;
    return AccionMotor.nada;
  }

  /// Abajo de esto, la camioneta está quieta (regla 3).
  static const double kmhQuieta = 5;

  /// Se llama cada tanto (la pantalla late una vez por segundo), con lo que
  /// lleva andado el viaje ([metros]) y la velocidad de ahora ([kmh]; `null`
  /// si el GPS todavía no la dio, y entonces cuenta como quieta).
  AccionMotor alLatir({
    required bool hayViaje,
    required int t,
    double metros = 0,
    double? kmh,
  }) {
    // Regla 3: andando no se cuenta la gracia; se vuelve a contar al parar.
    if (_sinCargaDesde != null && (kmh ?? 0) >= kmhQuieta) _sinCargaDesde = t;
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
