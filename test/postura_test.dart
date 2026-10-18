import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/vibracion/analisis.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';
import 'package:sitd_hilux/features/vibracion/postura.dart';
import 'package:sitd_hilux/features/vibracion/registro_vibracion.dart';
import 'package:sitd_hilux/features/vibracion/sacudon.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';

/// Una ventana de gravedad quieta en la dirección (x, y, z), sin normalizar.
void gravedad(Postura p, double x, double y, double z, {int n = 50}) {
  final m = math.sqrt(x * x + y * y + z * z);
  for (var i = 0; i < n; i++) {
    p.aceleracion(
      Sacudon(i, 9.81, x: 9.81 * x / m, y: 9.81 * y / m, z: 9.81 * z / m),
    );
  }
}

void girar(Postura p, double x, double y, double z, {int n = 50}) {
  for (var i = 0; i < n; i++) {
    p.giro(Giro(i, x, y, z));
  }
}

void main() {
  group('Postura (sitd-42): curvas', () {
    test('sin una parada no dice cuánto gira: el sesgo no se conoce', () {
      final p = Postura();
      girar(p, 0.028, 0.001, 0.026);
      expect(p.cerrar(40).giro, isNull);
    });

    test('parado mide el sesgo, y después lo descuenta', () {
      final p = Postura();
      // El Note 9 quieto: 0,038 rad/s que no son de nadie.
      girar(p, 0.028, 0.001, 0.026);
      expect(p.cerrar(0).giro, closeTo(0, 1e-9));
      // Andando derecho, el mismo sesgo: no es una curva.
      girar(p, 0.029, 0.0, 0.027);
      final derecho = p.cerrar(40).giro!;
      expect(derecho, lessThan(giroDeCurva));
      // Una esquina: 0,3 rad/s alrededor del eje del teléfono que sea.
      girar(p, 0.028, 0.3, 0.026);
      expect(p.cerrar(25).giro, closeTo(0.299, 1e-6));
    });
  });

  group('Postura (sitd-42): el teléfono se movió', () {
    test('la primera ventana legible es la referencia', () {
      final p = Postura();
      gravedad(p, 0, 1, 0.2);
      expect(p.cerrar(30).angulo, 0);
    });

    test('tres ventanas corridas más de 15° = se movió, y cambia la '
        'referencia', () {
      final p = Postura();
      gravedad(p, 0, 1, 0);
      p.cerrar(30);
      // 30° de corrimiento.
      final otra = [0.0, math.cos(math.pi / 6), math.sin(math.pi / 6)];
      for (var i = 0; i < 2; i++) {
        gravedad(p, otra[0], otra[1], otra[2]);
        final r = p.cerrar(30);
        expect(r.movido, isTrue);
        expect(r.seMovio, isNull);
      }
      gravedad(p, otra[0], otra[1], otra[2]);
      final r = p.cerrar(30);
      expect(r.seMovio, closeTo(30, 0.01));
      // La posición nueva es la referencia: ya no está corrido.
      gravedad(p, otra[0], otra[1], otra[2]);
      final despues = p.cerrar(30);
      expect(despues.movido, isFalse);
      expect(despues.angulo, closeTo(0, 0.01));
    });

    test('una frenada de una ventana no es «se movió»', () {
      final p = Postura();
      gravedad(p, 0, 1, 0);
      p.cerrar(30);
      gravedad(p, 0, 1, 0.3); // 16,7°
      expect(p.cerrar(30).seMovio, isNull);
      gravedad(p, 0, 1, 0);
      final r = p.cerrar(30);
      expect(r.movido, isFalse);
      gravedad(p, 0, 1, 0.3);
      gravedad(p, 0, 1, 0.3);
      expect(p.cerrar(30).seMovio, isNull);
    });

    test('en una curva no se mira la gravedad', () {
      final p = Postura();
      girar(p, 0, 0, 0);
      gravedad(p, 0, 1, 0);
      p.cerrar(0);
      for (var i = 0; i < 4; i++) {
        girar(p, 0, 0.3, 0);
        gravedad(p, 0, 1, 0.5); // la fuerza de la curva corre la gravedad
        final r = p.cerrar(30);
        expect(r.movido, isFalse);
        expect(r.seMovio, isNull);
      }
    });

    test('sin ejes (una fuente vieja) no hay ángulo', () {
      final p = Postura();
      p.aceleracion(const Sacudon(0, 9.8));
      expect(p.cerrar(30).angulo, isNull);
    });

    test('un viaje nuevo arranca sin referencia', () {
      final p = Postura();
      gravedad(p, 0, 1, 0);
      p.cerrar(30);
      p.nuevoViaje();
      gravedad(p, 1, 0, 0);
      expect(p.cerrar(30).angulo, 0);
    });
  });

  group('200 Hz (sitd-42)', () {
    List<double> senal(double hz, double segundos, List<double> fs) => [
      for (var i = 0; i < (hz * segundos).round(); i++)
        9.8 +
            fs.fold<double>(
              0,
              (s, f) => s + 0.3 * math.sin(2 * math.pi * f * i / hz),
            ),
    ];

    test('a 200 Hz el motor aparece en los picos, donde está', () {
      // 1.500 RPM → encendido en 50 Hz. Más una rueda a 7 Hz.
      final v = armarVentana(
        magnitud: senal(200, 5, [7, 50]),
        tInicio: 0,
        tFin: 4995,
        cubeta: 4,
      )!;
      expect(claseDeMuestreo(v.hz), 1);
      expect(v.picos, isNotEmpty);
      expect(v.picos[0], closeTo(50, 0.15));
    });

    test('a 50 Hz no hay picos: el motor no se ve', () {
      final v = armarVentana(
        magnitud: senal(50, 5, [7]),
        tInicio: 0,
        tFin: 4980,
        cubeta: 4,
      )!;
      expect(claseDeMuestreo(v.hz), 0);
      expect(v.picos, isEmpty);
    });

    test('la rueda sale en la misma banda y con la misma forma a 50 y a 200 '
        'Hz', () {
      final a = armarVentana(
        magnitud: senal(50, 5, [8.6]),
        tInicio: 0,
        tFin: 4980,
        cubeta: 4,
      )!;
      final b = armarVentana(
        magnitud: senal(200, 5, [8.6]),
        tInicio: 0,
        tFin: 4995,
        cubeta: 4,
      )!;
      final fa = formaDelEspectro(a.bandas)!, fb = formaDelEspectro(b.bandas)!;
      for (var i = 0; i < cantidadDeBandas; i++) {
        expect(fb[i], closeTo(fa[i], 0.02));
      }
    });

    test('a 50 Hz el motor se PLIEGA sobre la rueda; a 200 no', () {
      // Encendido en 41,4 Hz (1.240 RPM): muestreado a 50 cae en 8,6 Hz.
      final a = armarVentana(
        magnitud: senal(50, 5, [41.4]),
        tInicio: 0,
        tFin: 4980,
        cubeta: 4,
      )!;
      final b = armarVentana(
        magnitud: senal(200, 5, [41.4]),
        tInicio: 0,
        tFin: 4995,
        cubeta: 4,
      )!;
      final banda = bordesHz.lastIndexWhere((x) => x <= 8.6);
      expect(a.bandas[banda], greaterThan(10 * b.bandas[banda]));
    });
  });

  group('la clase vigente (sitd-42)', () {
    VentanaVibracion w(int t, double hz, {bool movido = false}) =>
        VentanaVibracion(
          t: t,
          cubeta: 2,
          hz: hz,
          muestras: 250,
          rms: 0.1,
          pico: 0.3,
          bandas: const [1, 1, 1, 1, 1, 1, 1, 1],
          movido: movido,
        );

    test('sólo entra la clase de la ventana más nueva', () {
      final porViaje = {
        1: [w(1, 49.85), w(2, 49.85)],
        2: [w(3, 199.4), w(4, 12.6)],
      };
      expect(claseVigente(porViaje), 1);
      final f = deLaClaseVigente(porViaje);
      expect(f[1], isEmpty);
      // La de 12,6 Hz se queda para que se cuente como «baja frecuencia».
      expect(f[2]!.map((v) => v.t), [3, 4]);
      expect(ventanasComparablesPorCubeta(f), {2: 1});
    });

    test('si el sistema vuelve a 50 Hz, vuelve a contar la historia vieja', () {
      final porViaje = {
        1: [w(1, 49.85)],
        2: [w(2, 199.4)],
        3: [w(3, 50.3)],
      };
      final f = deLaClaseVigente(porViaje);
      expect(f[1]!.length, 1);
      expect(f[2], isEmpty);
    });

    test('una ventana con el teléfono movido no se compara', () {
      expect(formaComparable(w(1, 199.4, movido: true)), isNull);
      expect(formaComparable(w(1, 199.4)), isNotNull);
    });
  });

  test('la base guarda y devuelve giro, ángulo, movido y picos', () {
    final base = Base.abrir(':memory:');
    final viajes = RegistroDeViajes(base);
    final r = RegistroDeVibracion(base);
    final id = viajes.abrir(inicio: 0);
    r.guardar(
      id,
      const VentanaVibracion(
        t: 5,
        cubeta: 3,
        hz: 199.4,
        muestras: 997,
        rms: 0.2,
        pico: 0.6,
        bandas: [1, 2, 3, 4, 5, 6, 7, 8],
        giro: 0.12,
        angulo: 3.5,
        movido: true,
        picos: [50.1, 12.3, 25.0, 4.1],
      ),
    );
    r.guardar(
      id,
      const VentanaVibracion(
        t: 10,
        cubeta: 3,
        hz: 49.85,
        muestras: 250,
        rms: 0.2,
        pico: 0.6,
        bandas: [1, 2, 3, 4, 5, 6, 7, 8],
      ),
    );
    final [a, b] = r.deViaje(id);
    expect(a.giro, 0.12);
    expect(a.angulo, 3.5);
    expect(a.movido, isTrue);
    expect(a.picos, [50.1, 12.3, 25.0, 4.1]);
    expect(b.giro, isNull);
    expect(b.movido, isFalse);
    expect(b.picos, isEmpty);
    expect(a.aMapa()['movido'], isTrue);
    expect(b.aMapa().containsKey('giro'), isFalse);
    viajes.cerrarRecursos();
    base.cerrar();
  });
}
