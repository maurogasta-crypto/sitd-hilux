import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/vibracion/analisis.dart';
import 'package:sitd_hilux/features/vibracion/cobertura.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';

void main() {
  group('cuánto sabe de una cubeta', () {
    test('sin una sola ventana lo dice, y dice cuánto hace falta', () {
      const c = CoberturaDeCubeta(cubeta: 4, ventanas: 0);
      expect(c.lista, isFalse);
      expect(c.faltan, ventanasParaLineaBase);
      expect(c.avance, 0);
      expect(c.comoVa, contains('Sin datos'));
      // Lo accionable es el tiempo, no el conteo.
      expect(c.comoVa, contains('2 min 30 s'));
    });

    test('a mitad de camino dice cuánto falta EN TIEMPO', () {
      const c = CoberturaDeCubeta(cubeta: 4, ventanas: 18);
      expect(c.lista, isFalse);
      expect(c.faltan, 12);
      expect(c.segundosQueFaltan, 60);
      expect(c.comoVa, contains('1 min'));
      expect(c.comoVa, contains('18 de 30'));
    });

    test('con las suficientes, el silencio ya significa algo', () {
      const c = CoberturaDeCubeta(cubeta: 4, ventanas: 30);
      expect(c.lista, isTrue);
      expect(c.faltan, 0);
      expect(c.segundosQueFaltan, 0);
      expect(c.avance, 1);
      expect(c.comoVa, contains('ya sabe qué es normal'));
    });

    test('de sobra no pasa de uno: es una barra, no un puntaje', () {
      const c = CoberturaDeCubeta(cubeta: 4, ventanas: 300);
      expect(c.avance, 1);
      expect(c.lista, isTrue);
    });
  });

  // Una cubeta que falta es justamente lo que hay que ver: dice a qué
  // velocidad hay que salir a andar. Si sólo se listaran las que tienen datos,
  // la pantalla se vería completa estando vacía.
  test('la cobertura lista TODAS las cubetas, incluidas las vacías', () {
    final c = cobertura({4: 30});
    expect(c.length, cubetaMaxima + 1);
    expect(c.where((x) => x.lista).length, 1);
    expect(c.firstWhere((x) => x.cubeta == 4).ventanas, 30);
    expect(c.firstWhere((x) => x.cubeta == 0).ventanas, 0);
  });

  test('una base vacía da todas las cubetas en cero, no una lista vacía', () {
    final c = cobertura(const {});
    expect(c.length, cubetaMaxima + 1);
    expect(c.every((x) => x.ventanas == 0), isTrue);
  });

  group('la rueda de ESTA camioneta', () {
    // Medido por Mauro el 2026-09-19: 76 cm bajo carga. La cubierta es una
    // 265/70R17, que sin carga da 80,3 cm — la diferencia es el achatamiento
    // por el peso, y es la razón por la que el factor de neumáticos se APRENDE
    // y no se calcula de la medida.
    test('el diámetro es el medido bajo carga, no el nominal', () {
      expect(diametroDeRuedaM, 0.76);
    });

    test('a 65 km/h la rueda gira a unas 7,6 vueltas por segundo', () {
      expect(vueltasPorSegundo(65), closeTo(7.56, 0.05));
    });

    test('a 110 km/h gira a unas 12,8, casi el doble', () {
      expect(vueltasPorSegundo(110), closeTo(12.80, 0.05));
    });

    // Es el porqué entero de las cubetas: el MISMO defecto cae en bandas
    // distintas según la velocidad. Sin separar por cubeta, se repartiría en
    // media docena de bandas y no se repetiría nunca igual.
    test('el mismo defecto cae en bandas distintas según la velocidad', () {
      final lenta = bandaDeLaRueda(65);
      final rapida = bandaDeLaRueda(110);
      expect(lenta, isNotNull);
      expect(rapida, isNotNull);
      expect(lenta, isNot(rapida));
      // 7,56 Hz cae en la banda 6-8; 12,8 Hz en la 10-13.
      expect(bordesHz[lenta!], 6);
      expect(bordesHz[rapida!], 10);
    });

    test('la velocidad típica de una cubeta es su centro', () {
      expect(velocidadTipicaDe(0), 25);
      expect(velocidadTipicaDe(4), 65);
    });

    test('toda cubeta medible cae dentro de alguna banda', () {
      for (var c = 0; c <= cubetaMaxima; c++) {
        expect(
          bandaDeLaRueda(velocidadTipicaDe(c)),
          isNotNull,
          reason: 'la cubeta $c queda fuera de las bandas que se miden',
        );
      }
    });
  });

  test('la ventana de la cobertura dura lo mismo que la del servicio', () {
    // Si alguien cambia una y no la otra, el «falta un minuto» miente.
    expect(segundosPorVentana, 5);
  });
}
