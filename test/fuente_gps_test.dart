import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitd_hilux/features/odometro/fuente_gps.dart';

Position posicion({
  bool conVelocidad = true,
  bool conPrecision = true,
  bool conAltitud = true,
  bool conPrecisionVel = true,
  double velocidad = 20,
}) => Position(
  latitude: -34.9,
  longitude: -56.2,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
  accuracy: 4.5,
  altitude: 32.0,
  altitudeAccuracy: 3.0,
  heading: 180,
  headingAccuracy: 5,
  speed: velocidad,
  speedAccuracy: 0.4,
  hasAccuracy: conPrecision,
  hasAltitude: conAltitud,
  hasSpeed: conVelocidad,
  hasSpeedAccuracy: conPrecisionVel,
);

void main() {
  group('muestraDePosicion', () {
    test('una posicion completa se traduce entera', () {
      final m = muestraDePosicion(posicion())!;
      expect(m.t, 1700000000000);
      expect(m.lat, -34.9);
      expect(m.lon, -56.2);
      expect(m.alt, 32.0);
      expect(m.velocidad, 20);
      expect(m.precision, 4.5);
      expect(m.precisionVel, 0.4);
    });

    // La trampa entera del archivo. Android entrega speed == 0.0 cuando no
    // tiene el dato: copiarlo tal cual haría que un receptor sin fijar
    // satélites se leyera como una camioneta detenida, y el viaje saldría
    // corto sin un solo error en pantalla.
    test('sin velocidad Doppler NO se traduce, aunque speed sea 0', () {
      expect(muestraDePosicion(posicion(conVelocidad: false)), isNull);
      expect(
        muestraDePosicion(posicion(conVelocidad: false, velocidad: 0)),
        isNull,
      );
    });

    test('sin precision tampoco: no habria con que descartar una mala', () {
      expect(muestraDePosicion(posicion(conPrecision: false)), isNull);
    });

    test('lo opcional que falta queda en nulo, no en cero', () {
      final m = muestraDePosicion(
        posicion(conAltitud: false, conPrecisionVel: false),
      )!;
      expect(m.alt, isNull);
      expect(m.precisionVel, isNull);
      // Y lo que sí vino sigue estando.
      expect(m.velocidad, 20);
    });
  });

  group('los modos de pedir posiciones', () {
    // Existen porque el receptor no entregó NI UNA a cielo abierto, dos veces,
    // con cero lecturas. Con cero, el problema está antes del filtro: cada
    // modo saca una pieza del medio para ver cuál es.
    test('los tres tienen nombre en castellano y son distintos', () {
      final nombres = ModoGps.values.map(nombreDeModo).toSet();
      expect(nombres.length, ModoGps.values.length);
      for (final n in nombres) {
        expect(n, isNotEmpty);
      }
    });

    test('el normal lleva servicio en primer plano y proveedor de Google', () {
      final ajustes =
          FuenteGps(modo: ModoGps.normal).ajustesParaPruebas as AndroidSettings;
      expect(ajustes.foregroundNotificationConfig, isNotNull);
      expect(ajustes.forceLocationManager, isFalse);
    });

    test('sin notificación saca el servicio y deja el resto igual', () {
      final ajustes =
          FuenteGps(modo: ModoGps.sinNotificacion).ajustesParaPruebas
              as AndroidSettings;
      expect(ajustes.foregroundNotificationConfig, isNull);
      expect(ajustes.forceLocationManager, isFalse);
      expect(ajustes.distanceFilter, 0);
    });

    test('el receptor directo saltea Play Services', () {
      final ajustes =
          FuenteGps(modo: ModoGps.receptorDirecto).ajustesParaPruebas
              as AndroidSettings;
      expect(ajustes.forceLocationManager, isTrue);
    });

    // El filtro de distancia en cero no es un descuido: la integración
    // necesita muestras a intervalos parejos, y con filtro el receptor calla
    // cuando el vehículo está quieto — y ese hueco se lee como un corte.
    test('ningún modo pone filtro de distancia', () {
      for (final m in ModoGps.values) {
        expect(
          (FuenteGps(modo: m).ajustesParaPruebas as AndroidSettings)
              .distanceFilter,
          0,
        );
      }
    });
  });
}
