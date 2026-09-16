import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Una lectura del acelerómetro, ya sin depender del complemento.
///
/// Se guarda el **módulo** y no los tres ejes: no se sabe cómo quedó puesto el
/// teléfono en la cabina, y con un solo eje el mismo defecto daría números
/// distintos según cómo lo colgaron ese día.
class Sacudon {
  final int t;
  final double magnitud;

  const Sacudon(this.t, this.magnitud);
}

/// De dónde salen los sacudones. Interfaz por la misma razón que el GPS: el
/// banco de pruebas tiene que poder sacudir la camioneta sin una camioneta.
abstract class FuenteDeVibracion {
  Stream<Sacudon> get sacudones;
  Future<void> detener();
}

/// El acelerómetro del teléfono.
///
/// **El período que se pide no es el que se recibe.** Android trata
/// `SensorInterval` como una sugerencia y cada aparato entrega lo que puede —el
/// Helio G85 del Redmi Note 9 no va a dar lo mismo que el teléfono nuevo—, así
/// que la frecuencia real se mide de los sellos de tiempo, ventana por
/// ventana, y se guarda con el vector. Sin ese número, un vector viejo no se
/// puede volver a leer: las bandas se calculan con él.
class Acelerometro implements FuenteDeVibracion {
  /// `game` son unos 50 Hz, que dan un espectro hasta 25 Hz. Alcanza de sobra:
  /// lo mecánico de una camioneta vive abajo de 17 Hz.
  final Duration periodo;

  Acelerometro({this.periodo = SensorInterval.gameInterval});

  @override
  Stream<Sacudon> get sacudones =>
      accelerometerEventStream(samplingPeriod: periodo).map((e) {
        final t = e.timestamp.millisecondsSinceEpoch;
        return Sacudon(
          // Algunos aparatos entregan el sello de tiempo en cero. Un cero
          // haría que la frecuencia medida diera cualquier cosa, así que se
          // cae al reloj del sistema, que para medir un intervalo de cinco
          // segundos alcanza.
          t > 0 ? t : DateTime.now().millisecondsSinceEpoch,
          _magnitud(e),
        );
      });

  static double _magnitud(AccelerometerEvent e) =>
      _raiz(e.x * e.x + e.y * e.y + e.z * e.z);

  static double _raiz(double x) => x <= 0 ? 0 : math.sqrt(x);

  @override
  Future<void> detener() async {
    // El stream se corta cancelando la suscripción, igual que el del GPS.
  }
}
