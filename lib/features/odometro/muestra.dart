/// Una lectura del receptor GPS, ya normalizada y sin dependencias de Flutter
/// para que se pueda probar con `flutter test` sin emulador ni teléfono.
class Muestra {
  /// Milisegundos desde la época. Es el reloj del sistema, no el del satélite.
  final int t;
  final double lat;
  final double lon;

  /// Altitud en metros. Opcional: no todos los receptores la informan y su
  /// error es varias veces el horizontal.
  final double? alt;

  /// Velocidad sobre el suelo, en m/s, **tal como la informa el receptor**.
  /// No se calcula diferenciando posiciones: sale del corrimiento Doppler de
  /// la portadora. Por eso su error es de ~0,1 m/s contra los varios metros
  /// que tiene la posición.
  final double velocidad;

  /// Error estimado de la posición, en metros.
  final double precision;

  /// Error estimado de la velocidad, en m/s. Android no siempre lo da.
  final double? precisionVel;

  const Muestra({
    required this.t,
    required this.lat,
    required this.lon,
    required this.velocidad,
    required this.precision,
    this.alt,
    this.precisionVel,
  });
}

/// Un par (odómetro de fábrica, GPS) tomado sobre el mismo tramo, que es con
/// lo que se calcula el factor de corrección por neumáticos.
class ParCalibracion {
  /// Kilómetros que avanzó el odómetro del tablero.
  final double kmTablero;

  /// Kilómetros reales medidos por GPS en ese mismo tramo.
  final double kmGps;

  const ParCalibracion({required this.kmTablero, required this.kmGps});
}
