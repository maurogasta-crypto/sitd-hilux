import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/combustible/carga.dart';
import 'package:sitd_hilux/features/combustible/registro_cargas.dart';
import 'package:sitd_hilux/features/odometro/integrador.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/core/bitacora.dart';
import 'package:sitd_hilux/features/respaldo/reporte.dart';
import 'package:sitd_hilux/features/sensores/satelites.dart';
import 'package:sitd_hilux/features/vibracion/analisis.dart';
import 'package:sitd_hilux/features/vibracion/cobertura.dart';
import 'package:sitd_hilux/features/vibracion/espectro.dart';
import 'package:sitd_hilux/features/vibracion/registro_vibracion.dart';
import 'package:sitd_hilux/features/vibracion/ventana.dart';

void main() {
  late Base base;
  late RegistroDeViajes viajes;
  late RegistroDeCargas cargas;
  late RegistroDeVibracion vibraciones;

  /// Una coordenada real de Uruguay, para poder buscarla en el JSON.
  const lat = -34.90567;
  const lon = -56.18921;

  setUp(() {
    base = Base.abrir(':memory:');
    viajes = RegistroDeViajes(base);
    cargas = RegistroDeCargas(base);
    vibraciones = RegistroDeVibracion(base);

    final viaje = viajes.abrir(inicio: 1000, odoTablero: 254300);
    for (var i = 0; i < 10; i++) {
      viajes.guardarPunto(
        viaje,
        Muestra(
          t: 1000 + i * 1000,
          lat: lat + i * 0.0001,
          lon: lon + i * 0.0001,
          alt: 30,
          velocidad: 20,
          precision: 6,
          precisionVel: 0.3,
        ),
      );
    }
    viajes.cerrar(
      viaje,
      fin: 11000,
      odometria: const ResultadoOdometria(
        metros: 180,
        metrosHaversine: 175,
        muestrasUsadas: 10,
        muestrasDescartadas: 7,
        cortes: 1,
        msIntegrados: 9000,
        descartes: {MotivoDescarte.precisionMala: 7},
        precisionTipicaDescartada: 68,
      ),
      odoTablero: 254395,
      sinDoppler: 3,
    );
    vibraciones.guardar(
      viaje,
      VentanaVibracion(
        t: 5000,
        cubeta: 4,
        hz: 47.2,
        muestras: 236,
        rms: 0.21,
        pico: 0.9,
        bandas: List<double>.filled(8, 0.1),
      ),
    );
    cargas.guardar(
      const Carga(t: 2000, litros: 60, costo: 3900, odoTablero: 254300),
    );
  });

  tearDown(() {
    viajes.cerrarRecursos();
    base.cerrar();
  });

  /// Una bitácora con contenido de verdad, para que la prueba de coordenadas
  /// de abajo tenga algo que revisar. Con la bitácora vacía esa prueba pasaría
  /// sin ejercer nada, que es la peor clase de prueba verde.
  late Bitacora registro;

  Map<String, dynamic> reporte(Alcance alcance) => armarReporte(
    base: base,
    viajes: viajes,
    cargas: cargas,
    vibraciones: vibraciones,
    alcance: alcance,
    sello: 'sitd-7',
    ahora: 99999,
    registro: registro,
    satelites: const EstadoSatelites(
      disponible: true,
      enganchado: true,
      vistos: 11,
      usados: 0,
      mejorCn0: 24,
    ),
  );

  setUp(() {
    registro = Bitacora(reloj: () => 5)
      ..anotar(Origen.permiso, 'Permiso de ubicación: whileInUse.')
      ..anotar(Origen.gps, 'Pidiendo posiciones en modo Normal.')
      ..anotar(Origen.satelites, 'Ve 11, usa 0, mejor señal 24 dB-Hz');
  });

  group('el reporte para desarrollo', () {
    // La prueba que sostiene la regla del proyecto: el recorrido NO se pega en
    // un chat. Si alguien agrega un campo con coordenadas sin pensarlo, esto
    // falla antes de que el archivo salga del teléfono.
    test('NO lleva ni una coordenada, y se comprueba en el texto entero', () {
      final texto = jsonEncode(reporte(Alcance.paraDesarrollo));
      expect(texto, isNot(contains('"lat"')));
      expect(texto, isNot(contains('"lon"')));
      expect(texto, isNot(contains('-34.90')));
      expect(texto, isNot(contains('-56.18')));
      expect(texto, contains('"sinRecorrido":true'));
      // Y la comprobación tiene que estar mirando algo: si la bitácora o los
      // satélites se fueran del reporte, esta prueba quedaría verde sin
      // proteger nada.
      expect(texto, contains('whileInUse'));
      expect(texto, contains('"vistos":11'));
    });

    test('lleva la bitácora del intercambio con el sistema', () {
      final r = reporte(Alcance.paraDesarrollo);
      final b = r['bitacora'] as List;
      expect(b.length, 3);
      expect((b.first as Map)['origen'], 'permiso');
      expect((b.last as Map)['texto'], contains('24 dB-Hz'));
    });

    // Lo que pidió Mauro el 2026-09-19: poder levantar los parámetros para
    // entender los vectores y ajustar el código desde afuera del teléfono.
    test('lleva los PARÁMETROS con los que se calculó todo', () {
      final p =
          (reporte(Alcance.paraDesarrollo)['analisis'] as Map)['parametros']
              as Map;
      // Sin los bordes, un vector de 8 números no tiene unidades.
      expect(p['bordesHz'], bordesHz);
      expect(p['cantidadDeBandas'], cantidadDeBandas);
      expect(p['ventanasParaLineaBase'], ventanasParaLineaBase);
      expect(p['umbralDeDesvio'], umbralDeDesvio);
      expect(p['viajesSeguidosParaAvisar'], viajesSeguidosParaAvisar);
      expect(p['velocidadMinimaKmh'], velocidadMinimaKmh);
      expect(p['diametroDeRuedaM'], diametroDeRuedaM);
    });

    test('lleva la COBERTURA, con las cubetas vacías incluidas', () {
      final c =
          (reporte(Alcance.paraDesarrollo)['analisis'] as Map)['cobertura']
              as List;
      // Todas las cubetas, no sólo las que tienen datos: una que falta dice a
      // qué velocidad hay que salir a andar.
      expect(c.length, cubetaMaxima + 1);
      final primera = c.first as Map;
      expect(primera.containsKey('ventanas'), isTrue);
      expect(primera.containsKey('lista'), isTrue);
      expect(primera.containsKey('segundosQueFaltan'), isTrue);
      expect(primera['rango'], nombreDeCubeta(0));
      // Y en qué banda caería un defecto de rueda a esa velocidad.
      expect(primera['bandaDeLaRueda'], isNotNull);
    });

    test('lleva la LÍNEA BASE y las conclusiones', () {
      final a = reporte(Alcance.paraDesarrollo)['analisis'] as Map;
      expect(a.containsKey('lineaBase'), isTrue);
      expect(a.containsKey('anomalias'), isTrue);
    });

    test('el análisis tampoco lleva una coordenada', () {
      final texto = jsonEncode(reporte(Alcance.paraDesarrollo)['analisis']);
      expect(texto, isNot(contains('lat')));
      expect(texto, isNot(contains('lon')));
      expect(texto, isNot(contains('-34.90')));
    });

    test('lleva lo que ve la antena, que es lo que separa los dos mundos', () {
      final s = reporte(Alcance.paraDesarrollo)['satelites'] as Map;
      expect(s['vistos'], 11);
      expect(s['usados'], 0);
      expect(s['mejorCn0'], 24);
      // Cuántos satélites se ven no dice dónde está la camioneta.
      expect(s.containsKey('lat'), isFalse);
    });

    test('pero SÍ lleva lo que hace falta para diagnosticar', () {
      final v =
          (reporte(Alcance.paraDesarrollo)['viajes'] as List).single
              as Map<String, dynamic>;
      expect(v['metros'], 180);
      expect(v['descartadas'], 7);
      expect(v['sinDoppler'], 3);
      expect(v['precisionDescartada'], 68);
      expect(v['motivos'], {'precisionMala': 7});
      expect(v['cortes'], 1);
      expect(v['odoTableroIni'], 254300);
      expect(v['odoTableroFin'], 254395);
    });

    test('el resumen de las muestras dice qué llegó, sin decir dónde', () {
      final v =
          (reporte(Alcance.paraDesarrollo)['viajes'] as List).single
              as Map<String, dynamic>;
      final r = v['muestrasResumen'] as Map<String, dynamic>;
      expect(r['cuantas'], 10);
      expect((r['velocidadMs'] as Map)['mediana'], 20);
      expect((r['precisionM'] as Map)['max'], 6);
      // Una muestra por segundo: si esto diera 12, el receptor se está
      // quedando sin cielo o el sistema está durmiendo la aplicación.
      expect(r['segundosEntreMuestras'], closeTo(1, 0.001));
    });

    test('la vibración viaja entera: no tiene nada de dónde', () {
      final v =
          (reporte(Alcance.paraDesarrollo)['viajes'] as List).single
              as Map<String, dynamic>;
      final w = (v['vibraciones'] as List).single as Map<String, dynamic>;
      expect(w['hz'], 47.2);
      expect(w['cubeta'], 4);
      expect((w['bandas'] as List).length, 8);
    });

    test('las cargas van, que es lo que explica el consumo', () {
      final c =
          (reporte(Alcance.paraDesarrollo)['cargas'] as List).single
              as Map<String, dynamic>;
      expect(c['litros'], 60);
      expect(c['moneda'], 'UYU');
    });

    test('dice con qué sello y con qué esquema se armó', () {
      final r = reporte(Alcance.paraDesarrollo);
      expect((r['app'] as Map)['sello'], 'sitd-7');
      expect((r['app'] as Map)['esquemaDeLaBase'], base.version);
    });
  });

  group('el respaldo completo', () {
    test('ese SÍ lleva el recorrido, punto por punto', () {
      final r = reporte(Alcance.respaldoCompleto);
      final v = (r['viajes'] as List).single as Map<String, dynamic>;
      final puntos = v['puntos'] as List;
      expect(puntos.length, 10);
      expect((puntos.first as Map)['lat'], lat);
      expect(r['sinRecorrido'], isFalse);
      expect(r['reporte'], 'respaldo-completo');
    });

    test('y se distingue del otro con mirar una línea', () {
      expect(reporte(Alcance.paraDesarrollo)['reporte'], 'para-desarrollo');
      final v =
          (reporte(Alcance.paraDesarrollo)['viajes'] as List).single
              as Map<String, dynamic>;
      expect(v.containsKey('puntos'), isFalse);
    });
  });

  test('una base vacía da un reporte válido, no una excepción', () {
    final vacia = Base.abrir(':memory:');
    final vViajes = RegistroDeViajes(vacia);
    final r = armarReporte(
      base: vacia,
      viajes: vViajes,
      cargas: RegistroDeCargas(vacia),
      vibraciones: RegistroDeVibracion(vacia),
      alcance: Alcance.paraDesarrollo,
      sello: 'sitd-7',
      ahora: 1,
    );
    expect(r['viajes'], isEmpty);
    expect(r['cargas'], isEmpty);
    expect(() => jsonEncode(r), returnsNormally);
    vViajes.cerrarRecursos();
    vacia.cerrar();
  });

  test('un viaje que no registró nada explica por qué, igual', () {
    final id = viajes.abrir(inicio: 50000);
    viajes.cerrar(
      id,
      fin: 470000,
      odometria: const ResultadoOdometria(
        metros: 0,
        metrosHaversine: 0,
        muestrasUsadas: 0,
        muestrasDescartadas: 380,
        cortes: 0,
        msIntegrados: 0,
        descartes: {MotivoDescarte.precisionMala: 380},
        precisionTipicaDescartada: 1500,
      ),
      sinDoppler: 12,
    );
    final v =
        (reporte(Alcance.paraDesarrollo)['viajes'] as List).first
            as Map<String, dynamic>;
    expect(v['metros'], 0);
    expect((v['muestrasResumen'] as Map)['cuantas'], 0);
    // Y acá está la diferencia con una fila vacía: el porqué quedó escrito.
    expect(v['descartadas'], 380);
    expect(v['precisionDescartada'], 1500);
    expect(v['motivos'], {'precisionMala': 380});
  });
}
