import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/integrador.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';

Muestra m(int tMs, double v, {double lon = -56.2, double? alt, double? pv}) =>
    Muestra(
      t: tMs,
      lat: -34.9,
      lon: lon,
      alt: alt,
      velocidad: v,
      precision: 5,
      precisionVel: pv,
    );

void main() {
  late Base base;
  late RegistroDeViajes registro;

  setUp(() {
    base = Base.abrir(':memory:');
    registro = RegistroDeViajes(base);
  });

  tearDown(() {
    registro.cerrarRecursos();
    base.cerrar();
  });

  group('viajes', () {
    test('sin viajes no hay ninguno abierto', () {
      expect(registro.abierto, isNull);
      expect(registro.ultimos(), isEmpty);
    });

    test('abrir deja un viaje sin cerrar, y es el que se retoma', () {
      final id = registro.abrir(inicio: 1000, odoTablero: 254300);
      final abierto = registro.abierto;
      expect(abierto, isNotNull);
      expect(abierto!.id, id);
      expect(abierto.enMarcha, isTrue);
      expect(abierto.odoTableroIni, 254300);
      expect(abierto.fin, isNull);
    });

    test('cerrar deja el fin y el total escritos', () {
      final id = registro.abrir(inicio: 1000);
      registro.cerrar(
        id,
        fin: 61000,
        odometria: const ResultadoOdometria(
          metros: 1234.5,
          metrosHaversine: 1200,
          muestrasUsadas: 60,
          muestrasDescartadas: 2,
          cortes: 1,
          msIntegrados: 60000,
        ),
      );
      final v = registro.porId(id)!;
      expect(v.enMarcha, isFalse);
      expect(v.metros, 1234.5);
      expect(v.metrosHaversine, 1200);
      expect(v.cortes, 1);
      expect(v.duracionMs(0), 60000);
      expect(registro.abierto, isNull);
    });

    test('cerrar sin odometro no borra el que ya estaba', () {
      final id = registro.abrir(inicio: 1000, odoTablero: 254300);
      registro.cerrar(id, fin: 2000);
      expect(registro.porId(id)!.odoTableroIni, 254300);
      expect(registro.porId(id)!.odoTableroFin, isNull);
    });

    test('los ultimos vienen con el mas nuevo primero', () {
      registro.abrir(inicio: 1000);
      registro.abrir(inicio: 5000);
      registro.abrir(inicio: 3000);
      expect(registro.ultimos().map((v) => v.inicio), [5000, 3000, 1000]);
      expect(registro.ultimos(2).length, 2);
    });
  });

  group('puntos', () {
    test('se guardan enteros y vuelven en orden', () {
      final id = registro.abrir(inicio: 0);
      registro.guardarPunto(id, m(2000, 12, alt: 45.5, pv: 0.4));
      registro.guardarPunto(id, m(1000, 10));
      final puntos = registro.puntosDe(id);
      expect(puntos.map((p) => p.t), [1000, 2000]);
      expect(puntos[0].alt, isNull);
      expect(puntos[0].precisionVel, isNull);
      expect(puntos[1].alt, 45.5);
      expect(puntos[1].precisionVel, 0.4);
      expect(puntos[1].velocidad, 12);
    });

    test('cada viaje ve solo los suyos', () {
      final a = registro.abrir(inicio: 0);
      final b = registro.abrir(inicio: 10);
      registro.guardarPunto(a, m(1000, 10));
      registro.guardarPunto(b, m(1000, 20));
      registro.guardarPunto(b, m(2000, 20));
      expect(registro.puntosDe(a).length, 1);
      expect(registro.puntosDe(b).length, 2);
    });

    // Las claves foráneas están encendidas por PRAGMA, no por el esquema: si
    // alguien saca ese pragma, borrar un viaje dejaría sus puntos huérfanos
    // ocupando lugar para siempre, sin que nada falle.
    test('borrar un viaje se lleva sus puntos', () {
      final id = registro.abrir(inicio: 0);
      registro.guardarPunto(id, m(1000, 10));
      base.db.execute('DELETE FROM viajes WHERE id = ?', [id]);
      expect(registro.puntosDe(id), isEmpty);
    });
  });

  group('recalcular', () {
    test('rehace el total desde los puntos y pisa lo guardado', () {
      final id = registro.abrir(inicio: 0);
      for (var i = 0; i <= 10; i++) {
        registro.guardarPunto(id, m(i * 1000, 20, lon: -56.2 + i * 0.0002));
      }
      // Un total viejo, mal escrito a propósito.
      registro.actualizar(
        id,
        const ResultadoOdometria(
          metros: 99999,
          metrosHaversine: 0,
          muestrasUsadas: 0,
          muestrasDescartadas: 0,
          cortes: 0,
          msIntegrados: 0,
        ),
      );
      expect(registro.porId(id)!.metros, 99999);

      final r = registro.recalcular(id);
      expect(r.metros, closeTo(200, 0.001));
      expect(registro.porId(id)!.metros, closeTo(200, 0.001));
    });

    test('con criterios mas estrictos el mismo viaje da menos', () {
      final id = registro.abrir(inicio: 0);
      for (var i = 0; i <= 10; i++) {
        registro.guardarPunto(id, m(i * 1000, 20));
      }
      final flojo = registro.recalcular(id);
      final estricto = registro.recalcular(
        id,
        criterios: const CriteriosGps(velocidadMaxima: 15),
      );
      expect(flojo.metros, greaterThan(0));
      expect(estricto.metros, 0);
      expect(estricto.muestrasDescartadas, 11);
    });
  });
}
