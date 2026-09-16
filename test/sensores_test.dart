import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/sensores/sensores.dart';

void main() {
  group('el estado de un sensor', () {
    test('sin suscribir, no se está esperando nada todavía', () {
      expect(
        estadoDeSensor(
          suscripto: false,
          lecturas: 0,
          msDesdeQueArranco: 60000,
          msDesdeLaUltima: null,
        ),
        EstadoSensor.esperando,
      );
    });

    test('recien suscripto y sin datos: es temprano', () {
      expect(
        estadoDeSensor(
          suscripto: true,
          lecturas: 0,
          msDesdeQueArranco: 500,
          msDesdeLaUltima: null,
        ),
        EstadoSensor.esperando,
      );
    });

    // Android NO avisa que un sensor no existe: la suscripción se abre igual y
    // el stream nunca emite. Sin este estado, un teléfono sin giróscopo se ve
    // exactamente igual que uno cuyo giróscopo se colgó.
    test('suscripto, pasado el tiempo de gracia y mudo: no contesta', () {
      expect(
        estadoDeSensor(
          suscripto: true,
          lecturas: 0,
          msDesdeQueArranco: msDeGracia + 1,
          msDesdeLaUltima: null,
        ),
        EstadoSensor.mudo,
      );
    });

    test('entregando: mide', () {
      expect(
        estadoDeSensor(
          suscripto: true,
          lecturas: 120,
          msDesdeQueArranco: 10000,
          msDesdeLaUltima: 40,
        ),
        EstadoSensor.midiendo,
      );
    });

    test(
      'entregaba y se calló: se cortó, que no es lo mismo que no contestar',
      () {
        expect(
          estadoDeSensor(
            suscripto: true,
            lecturas: 120,
            msDesdeQueArranco: 60000,
            msDesdeLaUltima: msParaCorte + 1,
          ),
          EstadoSensor.cortado,
        );
      },
    );

    test('cada estado tiene un nombre en castellano', () {
      for (final e in EstadoSensor.values) {
        expect(nombreDeEstado(e), isNotEmpty);
      }
      expect(nombreDeEstado(EstadoSensor.mudo), 'No contesta');
    });
  });

  group('la frecuencia medida', () {
    test('con una sola lectura no se inventa un numero', () {
      final m = MedidorDeFrecuencia();
      expect(m.hz, isNull);
      m.anotar(1000);
      expect(m.hz, isNull);
      expect(m.lecturas, 1);
      expect(m.ultimo, 1000);
    });

    test('cada 20 ms son 50 Hz', () {
      final m = MedidorDeFrecuencia();
      for (var i = 0; i < 30; i++) {
        m.anotar(i * 20);
      }
      expect(m.hz, closeTo(50, 0.001));
    });

    test('si el sistema entrega mas lento, el numero lo dice', () {
      final m = MedidorDeFrecuencia();
      for (var i = 0; i < 30; i++) {
        m.anotar(i * 60); // ~16,7 Hz
      }
      expect(m.hz, closeTo(16.67, 0.01));
    });

    test('la ventana olvida lo viejo: el numero sigue al cambio', () {
      final m = MedidorDeFrecuencia(ventana: 10);
      for (var i = 0; i < 10; i++) {
        m.anotar(i * 20); // 50 Hz
      }
      expect(m.hz, closeTo(50, 0.001));
      var t = 200;
      for (var i = 0; i < 10; i++) {
        t += 100; // 10 Hz
        m.anotar(t);
      }
      expect(m.hz, closeTo(10, 0.001));
      // Pero el total cuenta todas, no sólo las de la ventana.
      expect(m.lecturas, 20);
    });

    test('dos lecturas con el mismo sello no dividen por cero', () {
      final m = MedidorDeFrecuencia();
      m.anotar(1000);
      m.anotar(1000);
      expect(m.hz, isNull);
    });

    test('reiniciar deja el medidor como nuevo', () {
      final m = MedidorDeFrecuencia();
      for (var i = 0; i < 5; i++) {
        m.anotar(i * 20);
      }
      m.reiniciar();
      expect(m.hz, isNull);
      expect(m.lecturas, 0);
      expect(m.ultimo, isNull);
    });
  });
}
