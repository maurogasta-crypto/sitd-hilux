import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/audio/regimen.dart';
import 'package:sitd_hilux/features/audio/tacometro.dart';

/// El banco del tacómetro (`sitd-39`): la marcha que se oye juntando
/// escuchas, y las RPM que da el GPS con ella.
///
/// El caso que manda es el VIAJE 23 (16-oct-2026, 11 minutos de ciudad): sus
/// 28 escuchas reales, tal como subieron —el instante, la velocidad y cuánto
/// sonó cada marcha—. Son números, sin una coordenada. Con la regla vieja (una
/// escucha sola, 6 dB y 3 de ventaja) daban 4 de 28 con marcha.
const viaje23 = <(int, double, List<double?>)>[
  (0, 37.5, <double?>[4.6, 7.1, 8.9, 2.8, null]),
  (4995, 38.1, <double?>[4.4, 5.8, 8.6, 2.4, null]),
  (9996, 38.6, <double?>[2.8, 2.8, 4.1, 4.2, null]),
  (44998, 38.7, <double?>[1.3, 3.7, 6.9, 2, null]),
  (50001, 44.5, <double?>[2.6, 4.2, 6.6, 4.9, 1.8]),
  (54999, 44.3, <double?>[2.8, 5.3, 7, 4.7, 2]),
  (60003, 47.3, <double?>[null, 2.1, 11.4, 7.3, 1.8]),
  (64998, 54.8, <double?>[null, 5.1, 6.8, 5.1, 2.3]),
  (69995, 54.5, <double?>[null, 1.8, 9, 2.7, 2.3]),
  (89994, 36.6, <double?>[2, 2.8, 2.7, 0.8, null]),
  (164995, 31.7, <double?>[2.5, 2.1, 3.4, null, null]),
  (169990, 38, <double?>[0.8, 2.5, 3.7, 2.4, null]),
  (174996, 43.5, <double?>[2, 2.8, 6.6, 4.9, 2.5]),
  (179998, 47.9, <double?>[null, 3.3, 8.1, 4, 1.8]),
  (189997, 32.8, <double?>[2.5, 2, 5, null, null]),
  (219998, 33.2, <double?>[2.5, 3.7, 2.7, null, null]),
  (250000, 30.7, <double?>[3.1, 0.2, 5.1, null, null]),
  (264996, 34.3, <double?>[2.3, 2.2, 3.6, null, null]),
  (274996, 31.5, <double?>[1.5, 0.8, 2.6, null, null]),
  (280002, 34.2, <double?>[1.7, 0.7, 3, null, null]),
  (284994, 36.5, <double?>[3, 1.6, 2.8, 1.1, null]),
  (394995, 36.5, <double?>[2.7, 1.7, 2.9, 2.7, null]),
  (399997, 37, <double?>[3.7, 3.7, 2.1, 0.8, null]),
  (404991, 40.4, <double?>[4.2, 4.9, 4.6, 3.6, null]),
  (409991, 37.6, <double?>[1.8, 2, 2.2, 3.6, null]),
  (469993, 35.9, <double?>[3.2, 3.2, 2, null, null]),
  (475001, 39.2, <double?>[1.8, 6.5, 7.5, 0.9, null]),
  (479995, 42.3, <double?>[4, 1.9, 3.6, 1.1, null]),
];

void main() {
  group('la marcha, con las escuchas juntas', () {
    test('el viaje 23: de 4 a 12 escuchas con marcha, todas 3.ª', () {
      final tac = Tacometro();
      var conMarcha = 0;
      final vistas = <int>{};
      int? antes;
      var tomadas = 0;
      for (final (t, kmh, porMarcha) in viaje23) {
        final ahora = tac.escuchar(t, kmh, porMarcha);
        if (ahora != null && ahora != antes) tomadas++;
        antes = ahora;
        final g = decidirMarcha([porMarcha]);
        if (g != null) vistas.add(g);
      }
      // Escucha por escucha, con la vara de juntas: nada fuera de la 3.ª.
      expect(vistas.difference({3}), isEmpty);
      // Juntas: cuántas deciden (recalculado con la misma ventana).
      final buf = <(int, List<double?>)>[];
      for (final (t, _, porMarcha) in viaje23) {
        buf.add((t, porMarcha));
        buf.removeWhere((e) => t - e.$1 > msEscuchaVigente);
        while (buf.length > escuchasJuntas) {
          buf.removeAt(0);
        }
        final g = decidirMarcha([for (final e in buf) e.$2]);
        if (g != null) {
          conMarcha++;
          expect(g, 3);
        }
      }
      expect(conMarcha, greaterThanOrEqualTo(10));
      // Y la marcha no salta: se tomó una sola vez (la 3.ª) en todo el viaje.
      expect(tomadas, 1);
    });

    test('una escucha sola y clara decide (como antes)', () {
      expect(
        decidirMarcha([
          <double?>[null, 2.1, 11.4, 7.3, 1.8],
        ]),
        3,
      );
    });

    test('ruido parejo: ninguna marcha', () {
      expect(
        decidirMarcha([
          <double?>[2.5, 2.1, 3.4, null, null],
          <double?>[0.8, 2.5, 3.7, 2.4, null],
          <double?>[2.0, 2.8, 2.7, 0.8, null],
        ]),
        isNull,
      );
    });

    test('dos marchas parejas: ninguna (la ventaja no alcanza)', () {
      expect(
        decidirMarcha([
          <double?>[null, 6.0, 6.5, null, null],
          <double?>[null, 6.4, 6.0, null, null],
        ]),
        isNull,
      );
    });

    test(
      'a 70 km/h la 2.ª serían 3.600 RPM: empatadas, gana la 4.ª (sitd-40)',
      () {
        final escuchas = [
          <double?>[null, 7.0, 3.0, 8.0, null],
          <double?>[null, 7.5, 3.5, 8.2, null],
        ];
        expect(decidirMarcha(escuchas, kmh: 70), 4);
        expect(
          decidirMarcha(escuchas, kmh: 45),
          2,
          reason: 'a 45, la 2.ª es creíble',
        );
      },
    );

    test('2.ª y 4.ª a una octava, empatadas: gana la 2.ª, y no compiten', () {
      expect(
        decidirMarcha([
          <double?>[null, 7.0, 3.0, 8.0, null],
          <double?>[null, 7.5, 3.5, 8.2, null],
        ]),
        2,
      );
    });
  });

  group('las RPM por el GPS con la marcha tomada', () {
    Tacometro conTercera() {
      final tac = Tacometro();
      tac.escuchar(0, 40, <double?>[null, 2.0, 11.0, 3.0, null]);
      return tac;
    }

    test('siguen a la velocidad cada segundo', () {
      final tac = conTercera();
      expect(tac.marcha, 3);
      final a = tac.leer(1000, 40)!;
      final b = tac.leer(2000, 45)!;
      expect(a.rpm, closeTo(40 * rpmPorKmh(3), 0.01));
      expect(b.rpm, closeTo(45 * rpmPorKmh(3), 0.01));
      expect(b.marcha, 3);
      expect(b.oidaHaceMs, 2000);
    });

    test('una escucha que no decide no suelta la marcha', () {
      final tac = conTercera();
      tac.escuchar(5000, 41, <double?>[null, 2.0, 2.5, 2.2, null]);
      expect(tac.leer(6000, 41)?.marcha, 3);
    });

    test('otra marcha oída con claridad la reemplaza', () {
      final tac = conTercera();
      tac.escuchar(20000, 50, <double?>[null, null, 2.0, 12.0, 3.0]);
      expect(tac.leer(21000, 50)?.marcha, 4);
    });

    test(
      'se suelta: parado, salto de velocidad, RPM imposibles, mucho rato',
      () {
        expect(conTercera().leer(1000, 3), isNull, reason: 'parado');
        expect(conTercera().leer(1000, null), isNull, reason: 'sin GPS');
        expect(conTercera().leer(1000, 60), isNull, reason: 'salto de 20 km/h');
        expect(
          conTercera().leer(msMarchaVigente + 1, 40),
          isNull,
          reason: 'viejo',
        );
        final tac = Tacometro()
          ..escuchar(0, 100, <double?>[null, null, 12.0, 2.0, 2.0]);
        expect(tac.leer(1000, 110), isNull, reason: '3.ª a 110: 3.950 RPM');
        // Y una vez soltada, no vuelve sola.
        final t2 = conTercera();
        expect(t2.leer(1000, 3), isNull);
        expect(t2.leer(2000, 40), isNull);
      },
    );

    test('despacio (embrague, ralentí) no se escucha para la marcha', () {
      final tac = Tacometro()
        ..escuchar(0, 8, <double?>[12.0, null, null, null, null]);
      expect(tac.marcha, isNull);
    });
  });
}
