import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sitd_hilux/features/odometro/fuente_gps.dart';

/// Una posición como las que llegan DE VERDAD desde Android.
///
/// **Ojo con cómo modela la ausencia, que es el punto entero del archivo.**
/// Cuando el receptor no midió algo, el lado nativo **omite la clave** y el
/// lado de Dart pone `0.0`; las banderas `has*` vienen siempre en `false` por
/// el error de `geolocator_android` 5.0.3. Así que «sin velocidad» acá quiere
/// decir velocidad y margen en cero, no una bandera apagada con los números
/// puestos — eso último no pasa en ningún teléfono.
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
  accuracy: conPrecision ? 4.5 : 0.0,
  altitude: conAltitud ? 32.0 : 0.0,
  altitudeAccuracy: 3.0,
  heading: 180,
  headingAccuracy: 5,
  speed: conVelocidad ? velocidad : 0.0,
  speedAccuracy: conVelocidad && conPrecisionVel ? 0.4 : 0.0,
);

void main() {
  pruebasDelErrorDelPaquete();

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

/// El error de `geolocator_android` 5.0.3 que hizo que este proyecto
/// descartara el 100 % de las posiciones del GPS, en cualquier teléfono.
///
/// `AndroidPosition.fromMap` llama a `Position.fromMap` —que calcula bien las
/// banderas `has*` mirando qué claves mandó el lado nativo— y después
/// construye un `AndroidPosition` copiando **sólo los números**. El
/// constructor ni siquiera acepta las banderas, así que caen a `false`.
///
/// **Estas pruebas son la red.** Si algún día el paquete se arregla, la
/// primera empieza a fallar y ahí se puede volver a confiar en las banderas.
void pruebasDelErrorDelPaquete() {
  group('el error de geolocator_android que costó tres días', () {
    // El mapa exacto que arma `LocationMapper.toHashMap` cuando el receptor SÍ
    // informó todo. Ver el archivo Java del paquete.
    Map<String, dynamic> comoLoMandaAndroid({
      double? accuracy = 7.5,
      double? speed = 12.3,
      double? speedAccuracy = 0.4,
      bool isMocked = false,
    }) => <String, dynamic>{
      'latitude': -34.9,
      'longitude': -56.2,
      'timestamp': 1789576665000,
      'is_mocked': isMocked,
      'accuracy': accuracy,
      'speed': speed,
      'speed_accuracy': speedAccuracy,
      // El lado nativo OMITE la clave cuando el sensor no midió el valor, y
      // ésa es justamente la forma que hay que reproducir: no manda la clave
      // con un nulo adentro, no la manda.
    }..removeWhere((_, v) => v == null);

    test(
      'REPRODUCE el error: las banderas vuelven en false aunque haya datos',
      () {
        final p = AndroidPosition.fromMap(comoLoMandaAndroid());

        // Los números llegan bien...
        expect(p.accuracy, 7.5);
        expect(p.speed, 12.3);
        expect(p.speedAccuracy, 0.4);
        // ...y las banderas mienten. Si esto empieza a fallar, el paquete se
        // arregló y `loQueTrae` puede volver a confiar en ellas.
        expect(p.hasAccuracy, isFalse, reason: 'si pasa a true, se arregló');
        expect(p.hasSpeed, isFalse, reason: 'si pasa a true, se arregló');
      },
    );

    test('y por eso una posición BUENA se aceptaba mal: ahora entra', () {
      final m = muestraDePosicion(
        AndroidPosition.fromMap(comoLoMandaAndroid()),
      );
      expect(m, isNotNull, reason: 'esto devolvía null y tiraba todo el GPS');
      expect(m!.velocidad, 12.3);
      expect(m.precision, 7.5);
      expect(m.precisionVel, 0.4);
    });

    test(
      'una camioneta DETENIDA entra, porque su margen de error la respalda',
      () {
        // speed = 0 legítimo: el receptor lo informó y le puso margen.
        final m = muestraDePosicion(
          AndroidPosition.fromMap(comoLoMandaAndroid(speed: 0.0)),
        );
        expect(m, isNotNull);
        expect(m!.velocidad, 0);
      },
    );

    // La regla del proyecto que NO se puede perder con este arreglo: un cero
    // sin respaldo no es una camioneta quieta, es un dato que no existe.
    test('pero un cero SIN respaldo se sigue descartando', () {
      final m = muestraDePosicion(
        AndroidPosition.fromMap(
          comoLoMandaAndroid(speed: null, speedAccuracy: null),
        ),
      );
      expect(m, isNull);
    });

    test('sin precisión tampoco entra: no habría con qué filtrar', () {
      final m = muestraDePosicion(
        AndroidPosition.fromMap(comoLoMandaAndroid(accuracy: null)),
      );
      expect(m, isNull);
    });

    test('loQueTrae respeta la bandera cuando dice que SÍ', () {
      // Lo que pasaría en iOS, o acá el día que el paquete se arregle.
      final p = Position(
        latitude: -34.9,
        longitude: -56.2,
        timestamp: DateTime.utc(2026, 9, 17),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        hasAccuracy: true,
        hasSpeed: true,
      );
      final trae = loQueTrae(p);
      expect(trae.precision, isTrue);
      expect(trae.velocidad, isTrue);
    });

    test('una posición SIMULADA se reconoce', () {
      final p = AndroidPosition.fromMap(comoLoMandaAndroid(isMocked: true));
      expect(p.isMocked, isTrue);
    });
  });
}
