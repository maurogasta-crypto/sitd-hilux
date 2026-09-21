import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/combustible/carga.dart';
import 'package:sitd_hilux/features/combustible/registro_cargas.dart';
import 'package:sitd_hilux/features/odometro/factor.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';

void main() {
  late Base base;
  late RegistroDeCargas cargas;
  late RegistroDeViajes viajes;

  setUp(() {
    base = Base.abrir(':memory:');
    cargas = RegistroDeCargas(base);
    viajes = RegistroDeViajes(base);
  });

  tearDown(() {
    viajes.cerrarRecursos();
    base.cerrar();
  });

  group('cargas', () {
    test('una carga vuelve entera de la base', () {
      cargas.guardar(
        const Carga(
          t: 1000,
          litros: 62.5,
          costo: 3900.75,
          moneda: 'UYU',
          odoTablero: 254321,
          tanqueLleno: false,
          estacion: 'Ancap del cruce',
          notas: 'olía a gasoil',
        ),
      );
      final c = cargas.todas().single;
      expect(c.litros, 62.5);
      expect(c.costo, 3900.75);
      expect(c.moneda, 'UYU');
      expect(c.odoTablero, 254321);
      expect(c.tanqueLleno, isFalse);
      expect(c.estacion, 'Ancap del cruce');
      expect(c.notas, 'olía a gasoil');
      expect(c.id, isNotNull);
    });

    test('lo que no valida no llega a la base', () {
      expect(
        () => cargas.guardar(const Carga(t: 0, litros: -1, odoTablero: 100)),
        throwsArgumentError,
      );
      expect(cargas.todas(), isEmpty);
    });

    test('vienen de la mas vieja a la mas nueva', () {
      cargas.guardar(const Carga(t: 3000, litros: 10, odoTablero: 300));
      cargas.guardar(const Carga(t: 1000, litros: 10, odoTablero: 100));
      cargas.guardar(const Carga(t: 2000, litros: 10, odoTablero: 200));
      expect(cargas.todas().map((c) => c.t), [1000, 2000, 3000]);
    });

    test('el ultimo odometro es el de la carga mas reciente', () {
      expect(cargas.ultimoOdometro, isNull);
      cargas.guardar(const Carga(t: 1000, litros: 10, odoTablero: 100));
      cargas.guardar(const Carga(t: 3000, litros: 10, odoTablero: 300));
      cargas.guardar(const Carga(t: 2000, litros: 10, odoTablero: 200));
      expect(cargas.ultimoOdometro, 300);
    });

    test('borrar saca una y deja las otras', () {
      final id = cargas.guardar(
        const Carga(t: 1000, litros: 10, odoTablero: 100),
      );
      cargas.guardar(const Carga(t: 2000, litros: 10, odoTablero: 200));
      cargas.borrar(id);
      expect(cargas.todas().single.t, 2000);
    });

    test('el tanque tiene un valor por defecto y se puede cambiar', () {
      expect(
        cargas.litrosDelTanque,
        RegistroDeCargas.litrosDelTanquePorDefecto,
      );
      cargas.litrosDelTanque = 76;
      expect(cargas.litrosDelTanque, 76);
      // Y sobrevive a otra instancia: está en `ajustes`, no en memoria.
      expect(RegistroDeCargas(base).litrosDelTanque, 76);
    });
  });

  group('pares de calibracion', () {
    int viajeDe({
      required double km,
      double? odoIni,
      double? odoFin,
      bool cerrado = true,
    }) {
      final id = viajes.abrir(inicio: 0, odoTablero: odoIni);
      // Un punto por kilómetro, a 20 m/s, para que el total sea el pedido.
      final segundos = (km * 1000 / 20).round();
      for (var i = 0; i <= segundos; i++) {
        viajes.guardarPunto(
          id,
          Muestra(
            t: i * 1000,
            lat: -34.9,
            lon: -56.2,
            velocidad: 20,
            precision: 5,
          ),
        );
      }
      viajes.recalcular(id);
      if (cerrado) {
        viajes.cerrar(id, fin: segundos * 1000, odoTablero: odoFin);
      }
      return id;
    }

    test('sin viajes anotados no hay factor, y no se inventa uno', () {
      expect(viajes.paresDeCalibracion(), isEmpty);
      expect(factorRobusto(viajes.paresDeCalibracion()), isNull);
    });

    test('un viaje sin odometro anotado no entra', () {
      viajeDe(km: 100);
      expect(viajes.paresDeCalibracion(), isEmpty);
    });

    test('un viaje anotado en las dos puntas da su par', () {
      viajeDe(km: 100, odoIni: 254000, odoFin: 254095);
      final pares = viajes.paresDeCalibracion();
      expect(pares.length, 1);
      expect(pares.single.kmTablero, 95);
      expect(pares.single.kmGps, closeTo(100, 0.01));
    });

    // Neumáticos más grandes: el GPS mide más de lo que cuenta el tablero, y
    // el factor sale mayor que 1. Es la dirección que se confunde siempre.
    test('con neumaticos mas grandes el factor da mayor que uno', () {
      viajeDe(km: 100, odoIni: 1000, odoFin: 1095);
      viajeDe(km: 200, odoIni: 2000, odoFin: 2190);
      final f = factorRobusto(viajes.paresDeCalibracion())!;
      expect(f.k, greaterThan(1));
      expect(f.k, closeTo(100 / 95, 0.01));
      expect(f.pares, 2);
      // Y traduce: lo que el tablero dice que son 100 km, fueron más.
      expect(f.aReal(100), greaterThan(100));
    });

    /* ── LO QUE AGREGÓ `sitd-22` ──────────────────────────────────────────
       Un viaje bien anotado en las dos puntas TAMPOCO calibra si el GPS no lo
       midió entero. Lo marcó Mauro sobre el viaje del 2026-09-20: «se puede
       desestimar ese valor porque no había comenzado a medir desde el
       inicio». Si faltan kilómetros del lado del GPS, el factor sale más
       chico y nada avisa. */
    test(
      'un viaje que el GPS no midio entero no da par, aunque este anotado',
      () {
        final id = viajes.abrir(inicio: 0, odoTablero: 1000);
        /* Empieza a medir recién a los 500 s de 5000: el tablero contó ese
           tramo y el GPS no. Cobertura 90 %, contra el 98 % que pide
           `sirveParaCalibrar` — y la proporción no es de adorno, es la del
           caso real, donde aquel viaje llegó al 92,9 %.

           OJO CON ESTE NÚMERO. La primera versión de esta prueba dejaba
           afuera UN MINUTO de 5000 s, que da 98,8 % y CALIFICA: el hueco era
           más chico que el umbral, así que la prueba pasaba por el lado
           equivocado y afirmaba lo contrario de lo que dice su nombre. La
           corrida la agarró. Si algún día se afloja `coberturaMinima`, este
           500 hay que volver a calcularlo. */
        for (var i = 500; i <= 5000; i++) {
          viajes.guardarPunto(
            id,
            Muestra(
              t: i * 1000,
              lat: -34.9,
              lon: -56.2,
              velocidad: 20,
              precision: 5,
            ),
          );
        }
        viajes.recalcular(id);
        viajes.cerrar(id, fin: 5000 * 1000, odoTablero: 1095);
        expect(viajes.paresDeCalibracion(), isEmpty);
      },
    );

    test('un viaje que lo midio entero si da su par', () {
      // El mismo de arriba, sin el minuto perdido. Es el control: sin esto,
      // la prueba anterior pasaría aunque `paresDeCalibracion` estuviera rota.
      viajeDe(km: 100, odoIni: 1000, odoFin: 1095);
      expect(viajes.paresDeCalibracion(), hasLength(1));
    });

    test('un viaje sin cerrar todavia no cuenta', () {
      viajeDe(km: 100, odoIni: 1000, odoFin: 1095, cerrado: false);
      expect(viajes.paresDeCalibracion(), isEmpty);
    });

    test('un odometro que retrocede no entra', () {
      viajeDe(km: 100, odoIni: 2000, odoFin: 1000);
      expect(viajes.paresDeCalibracion(), isEmpty);
    });
  });
}
