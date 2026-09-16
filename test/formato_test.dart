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
}
