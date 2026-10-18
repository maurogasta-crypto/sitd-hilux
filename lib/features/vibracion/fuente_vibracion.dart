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

/// De dónde sale el giro (`sitd-42`). Puede no haber: el Redmi 15 no tiene
/// giróscopo, y entonces el stream no emite nunca y todo sigue como antes.
abstract class FuenteDeGiro {
  Stream<Giro> get giros;
}

/// El giróscopo del teléfono, a unos 50 Hz: para saber si la camioneta dobla
/// y si el teléfono se mueve no hace falta más, y cada evento cruza el canal
/// de la plataforma.
class Giroscopo implements FuenteDeGiro {
  @override
  Stream<Giro> get giros =>
      gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
          .map((e) {
            final t = e.timestamp.millisecondsSinceEpoch;
            return Giro(
              t > 0 ? t : DateTime.now().millisecondsSinceEpoch,
              e.x,
              e.y,
              e.z,
            );
          });
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
  /// **Desde `sitd-42` se pide lo más rápido** (`fastest`). Hasta ahí se
  /// pedía `game`, unos 50 Hz, que daban un espectro hasta 24,93 Hz: alcanza
  /// para la rueda y NO para el motor —el encendido está en RPM/30, 26,7 Hz a
  /// ralentí—, que además se plegaba y aparecía abajo, donde no está.
  ///
  /// El 2026-10-18 Mauro midió con «Probar la medición»: **el Redmi 15 da
  /// 199,4 Hz y el Note 9 201,3, los dos sin un faltante.** Con eso el
  /// espectro llega a 100 Hz: el motor se ve hasta unas 3.000 RPM y ya no se
  /// cuela en las bandas de la rueda. Las bandas siguen siendo las mismas;
  /// lo que cambia es que se miden limpias (ver `claseDeMuestreo`).
  final Duration periodo;

  Acelerometro({this.periodo = SensorInterval.fastestInterval});

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
          x: e.x,
          y: e.y,
          z: e.z,
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
