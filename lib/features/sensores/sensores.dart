/// En qué anda un sensor. Es lo que contesta la pregunta «¿esto se está
/// comunicando?», que hasta ahora no se podía hacer desde el teléfono.
enum EstadoSensor {
  /// Se pidió y todavía no llegó nada, pero es temprano para preocuparse.
  esperando,

  /// Está entregando.
  midiendo,

  /// Se pidió, pasó el tiempo de gracia y nunca entregó nada.
  ///
  /// **Android no avisa que un sensor no existe.** Si el teléfono no tiene
  /// giróscopo, la suscripción se abre igual y el stream simplemente no emite
  /// nunca: idéntico a un sensor que está pero no contesta. Este estado es esa
  /// diferencia, y la única forma de verla es el reloj.
  mudo,

  /// Entregaba y dejó de hacerlo.
  cortado,

  /// Falta un permiso.
  sinPermiso,

  /// Dio error.
  falla,
}

/// Cuánto se espera antes de decir que un sensor no contesta.
///
/// Cuatro segundos alcanzan para un acelerómetro, que entrega cincuenta veces
/// por segundo. **Para el GPS no**: un receptor frío tarda entre treinta
/// segundos y un minuto en fijar satélites, así que decirle «no contesta» a
/// los cuatro segundos es acusarlo de algo que todavía no hizo. Por eso son
/// dos números, y por eso la pantalla muestra además hace cuánto que espera:
/// «esperando» a los tres segundos y «esperando» a los tres minutos son cosas
/// muy distintas y sin el reloj se leen igual.
const int msDeGracia = 4000;

/// El del GPS: un minuto y medio, que es más de lo que tarda un arranque frío
/// a cielo abierto.
const int msDeGraciaGps = 90000;

/// Cuánto silencio, después de haber entregado, cuenta como corte.
const int msParaCorte = 5000;

/// Decide el estado de un sensor a partir de los tiempos. Sin widgets ni
/// streams: es una función, y por eso se puede probar.
EstadoSensor estadoDeSensor({
  required bool suscripto,
  required int lecturas,
  required int msDesdeQueArranco,
  required int? msDesdeLaUltima,
  int gracia = msDeGracia,
}) {
  if (!suscripto) return EstadoSensor.esperando;
  if (lecturas == 0) {
    return msDesdeQueArranco >= gracia
        ? EstadoSensor.mudo
        : EstadoSensor.esperando;
  }
  if (msDesdeLaUltima != null && msDesdeLaUltima >= msParaCorte) {
    return EstadoSensor.cortado;
  }
  return EstadoSensor.midiendo;
}

/// Cómo se dice cada estado, en palabras y no en jerga.
String nombreDeEstado(EstadoSensor e) => switch (e) {
  EstadoSensor.esperando => 'Esperando',
  EstadoSensor.midiendo => 'Midiendo',
  EstadoSensor.mudo => 'No contesta',
  EstadoSensor.cortado => 'Se cortó',
  EstadoSensor.sinPermiso => 'Sin permiso',
  EstadoSensor.falla => 'Falló',
};

/// Mide a qué frecuencia está llegando algo, de los tiempos de llegada.
///
/// **No se usa la frecuencia que se le pidió al sistema.** Android trata el
/// período como una sugerencia: pedirle 50 Hz y recibir 45, o 17, es normal y
/// depende del aparato, de si la pantalla está apagada y de lo que esté
/// haciendo el resto del teléfono. El número que sirve es el medido, y es el
/// que la pantalla muestra.
class MedidorDeFrecuencia {
  /// Cuántas llegadas se recuerdan. Con una ventana corta el número tiembla;
  /// con una larga tarda en reaccionar cuando el sistema baja la frecuencia.
  final int ventana;

  final List<int> _tiempos = [];
  int _total = 0;

  MedidorDeFrecuencia({this.ventana = 30});

  void anotar(int t) {
    _total++;
    _tiempos.add(t);
    if (_tiempos.length > ventana) _tiempos.removeAt(0);
  }

  int get lecturas => _total;
  int? get ultimo => _tiempos.isEmpty ? null : _tiempos.last;

  /// Hertz medidos, o `null` mientras no haya con qué calcularlos.
  double? get hz {
    if (_tiempos.length < 2) return null;
    final lapso = _tiempos.last - _tiempos.first;
    if (lapso <= 0) return null;
    return (_tiempos.length - 1) * 1000 / lapso;
  }

  void reiniciar() {
    _tiempos.clear();
    _total = 0;
  }
}
