import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import 'sacudon.dart';

// Se reexporta para que las once cosas que ya importaban `Sacudon` de acá
// sigan andando sin tocar una línea. Lo que cambió es que ahora se PUEDE
// importar sin arrastrar el complemento — ver `sacudon.dart`.
export 'sacudon.dart';

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
  /// `game` son unos 50 Hz pedidos, que en el Redmi 15 dan 49,85 medidos y un
  /// espectro hasta 24,93 Hz.
  ///
  /// **Alcanza para lo mecánico de la camioneta y NO alcanza para el motor**,
  /// y esa segunda mitad recién quedó clara el 2026-09-22. El encendido de un
  /// 4 cilindros de 4 tiempos está en RPM/30: 26,7 Hz a ralentí, o sea ya por
  /// encima de Nyquist antes de arrancar. No es que se vea mal — es que se
  /// pliega y aparece abajo, donde no está. Ver `calidad.dart`.
  final Duration periodo;

  Acelerometro({this.periodo = SensorInterval.gameInterval});

  @override
  Stream<Sacudon> get sacudones =>
      accelerometerEventStream(samplingPeriod: periodo).map((e) {
        final t = e.timestamp.millisecondsSinceEpoch;
        final u = e.timestamp.microsecondsSinceEpoch;
        // Algunos aparatos entregan el sello de tiempo en cero. Un cero haría
        // que la frecuencia medida diera cualquier cosa, así que se cae al
        // reloj del sistema, que para medir un intervalo de cinco segundos
        // alcanza. **Los dos relojes se leen UNA vez**: leerlos por separado
        // dejaría `t` y `tMicro` describiendo instantes distintos.
        final ahora = DateTime.now();
        return Sacudon(
          t > 0 ? t : ahora.millisecondsSinceEpoch,
          _magnitud(e),
          micros: t > 0 ? u : ahora.microsecondsSinceEpoch,
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
