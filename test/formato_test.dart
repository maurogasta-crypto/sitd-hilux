import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/ui/formato.dart';

void main() {
  group('formatearKm', () {
    test('abajo de 100 km va con una decimal y coma', () {
      expect(formatearKm(0), '0,0 km');
      expect(formatearKm(12.34), '12,3 km');
      expect(formatearKm(99.95), '100,0 km');
    });

    test('de 100 km para arriba, sin decimales', () {
      expect(formatearKm(100), '100 km');
      expect(formatearKm(254321.6), '254322 km');
    });
  });

  group('formatearDuracion', () {
    test('abajo del minuto manda el segundero', () {
      expect(formatearDuracion(0), '0 s');
      expect(formatearDuracion(45000), '45 s');
    });

    test('de un minuto a una hora, minutos', () {
      expect(formatearDuracion(60000), '1 min');
      expect(formatearDuracion(59 * 60000 + 59000), '59 min');
    });

    test('de una hora para arriba, horas y minutos con cero adelante', () {
      expect(formatearDuracion(3600000), '1 h 00 min');
      expect(formatearDuracion(3600000 + 7 * 60000), '1 h 07 min');
      expect(formatearDuracion(25 * 3600000), '25 h 00 min');
    });

    test('un tiempo negativo no muestra un menos: muestra cero', () {
      // Pasa de verdad: el reloj del sistema se corrige y el inicio del viaje
      // queda adelante de ahora.
      expect(formatearDuracion(-5000), '0 s');
    });
  });

  group('combustible', () {
    test('litros y consumo van con coma', () {
      expect(formatearLitros(62.53), '62,5 L');
      expect(formatearConsumo(10.24), '10,2 L/100 km');
    });

    test('la plata lleva su moneda adelante, y nunca se suman dos', () {
      expect(formatearDinero(3900.5, 'UYU'), 'UYU 3901');
      expect(formatearDinero(60.25, 'USD'), 'USD 60,25');
      // Abajo de mil se ven los centésimos; arriba no le sirven a nadie.
      expect(formatearDinero(999.994, 'UYU'), 'UYU 999,99');
    });

    test('una fecha corta se lee como la diria alguien', () {
      final t = DateTime(2026, 9, 5, 21, 30).millisecondsSinceEpoch;
      expect(formatearFecha(t), '05/09');
    });
  });

  group('la fecha con hora', () {
    test('dice día, mes y hora, sin segundos', () {
      final t = DateTime(2026, 9, 21, 20, 27, 49).millisecondsSinceEpoch;
      expect(formatearFechaYHora(t), '21/09 20:27');
    });

    test('rellena con cero a la izquierda', () {
      final t = DateTime(2026, 1, 5, 7, 3).millisecondsSinceEpoch;
      expect(formatearFechaYHora(t), '05/01 07:03');
    });

    test('distingue dos viajes del MISMO día, que es para lo que existe', () {
      /* Es el caso real del 2026-09-21: uno a las 19:52 y otro a las 20:27.
         Con `formatearFecha` sola los dos dicen «21/09» y no hay forma de
         elegir cuál traer de la nube. */
      final tarde = DateTime(2026, 9, 21, 19, 52).millisecondsSinceEpoch;
      final noche = DateTime(2026, 9, 21, 20, 27).millisecondsSinceEpoch;
      expect(formatearFecha(tarde), formatearFecha(noche));
      expect(formatearFechaYHora(tarde), isNot(formatearFechaYHora(noche)));
    });
  });
}
