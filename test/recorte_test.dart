import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/nube/recorte.dart';

/// Un reporte con [ventanas] ventanas de vibración, del tamaño que tendrían
/// las de verdad.
Map<String, dynamic> reporteCon(int ventanas, {bool conBitacora = true}) => {
  'reporte': 'para-desarrollo',
  'generado': 1789842936348,
  'app': {'sello': 'sitd-18'},
  'sinRecorrido': true,
  if (conBitacora)
    'bitacora': [
      for (var i = 0; i < 300; i++)
        {
          't': 1789842936348 + i,
          'origen': 'gps',
          'texto': 'Una línea de bitácora como las que escribe la aplicación.',
        },
    ],
  'viajes': [
    {
      'id': 7,
      'inicio': 1000,
      'fin': 2000,
      'metros': 12345.6,
      'vibraciones': [
        for (var i = 0; i < ventanas; i++)
          {
            't': 1789842936348 + i * 5000,
            'cubeta': i % 10,
            'hz': 49.87654321,
            'muestras': 249,
            'rms': 0.4123456789,
            'pico': 1.9876543210,
            'bandas': [
              0.012345678,
              0.023456789,
              0.034567891,
              0.045678912,
              0.056789123,
              0.067891234,
              0.078912345,
              0.089123456,
            ],
          },
      ],
    },
  ],
};

int pesar(Object? x) => utf8.encode(jsonEncode(x)).length;

void main() {
  test('un reporte chico pasa intacto y lo dice', () {
    final r = reporteCon(10);
    final listo = recortarParaSubir(r);

    expect(listo.recorte.huboRecorte, isFalse);
    expect(listo.reporte.containsKey('recorte'), isFalse);
    expect(listo.reporte['bitacora'], isNotNull);
    expect(listo.recorte.vibracionesDespues, 10);
  });

  test('si no entra, lo PRIMERO que se va es la bitácora', () {
    // Un tope que deja pasar el viaje pero no la bitácora. El margen cubre la
    // nota de recorte, que a partir de acá va siempre en el documento.
    final r = reporteCon(20);
    final tope = pesar(reporteCon(20, conBitacora: false)) + 400;
    final listo = recortarParaSubir(r, tope: tope);

    expect(listo.recorte.bitacoraQuitada, isTrue);
    expect(listo.reporte.containsKey('bitacora'), isFalse);
    // La vibración, que es lo que no se puede reconstruir, quedó entera.
    expect(listo.recorte.vibracionesDespues, 20);
  });

  test('si todavía no entra, se diezma la vibración PAREJO', () {
    final listo = recortarParaSubir(reporteCon(100), tope: 4000);

    expect(listo.recorte.vibracionesAntes, 100);
    expect(listo.recorte.vibracionesDespues, lessThan(100));
    expect(listo.recorte.vibracionesDespues, greaterThan(0));

    // Parejo quiere decir a lo largo del viaje entero, no las primeras N. Un
    // viaje recortado por el principio mentiría sobre a qué velocidad anduvo.
    final quedaron =
        ((listo.reporte['viajes'] as List).single as Map)['vibraciones']
            as List;
    final cubetas = {for (final v in quedaron) (v as Map)['cubeta']};
    expect(
      cubetas.length,
      greaterThan(1),
      reason: 'si quedaran sólo las primeras, sería una sola cubeta',
    );
    final tiempos = [for (final v in quedaron) (v as Map)['t'] as int];
    expect(tiempos.last - tiempos.first, greaterThan(400000));
  });

  test('pase lo que pase, el resultado ENTRA en el tope', () {
    for (final ventanas in [0, 1, 50, 500, 5000]) {
      for (final tope in [1500, 5000, 50000, topeDelDocumento]) {
        final listo = recortarParaSubir(reporteCon(ventanas), tope: tope);
        if (!listo.recorte.noEntro) {
          expect(
            pesar(listo.reporte),
            lessThanOrEqualTo(tope),
            reason: '$ventanas ventanas con tope $tope',
          );
        }
      }
    }
  });

  // Nunca se recorta en silencio: un vector que falta se tiene que poder
  // explicar seis meses después en vez de parecer un hueco raro.
  test('el documento dice QUÉ se le sacó', () {
    final listo = recortarParaSubir(reporteCon(200), tope: 6000);
    final nota = listo.reporte['recorte'] as Map;

    expect(nota['porque'], contains('no entraba'));
    expect(nota['bitacoraQuitada'], isTrue);
    expect(nota['ventanasDeVibracionAntes'], 200);
    expect(nota['ventanasDeVibracionDespues'], lessThan(200));
  });

  test('si ni pelado entra, lo dice en vez de reintentar para siempre', () {
    final listo = recortarParaSubir(reporteCon(100), tope: 10);
    expect(listo.recorte.noEntro, isTrue);
    expect(listo.recorte.vibracionesDespues, 0);
  });

  test('no toca el reporte original: la pantalla lo sigue usando', () {
    final r = reporteCon(100);
    final antes = pesar(r);
    recortarParaSubir(r, tope: 3000);

    expect(pesar(r), antes);
    expect(r['bitacora'], isNotNull);
    expect(
      ((r['viajes'] as List).single as Map)['vibraciones'],
      hasLength(100),
    );
  });

  // El tope de Firestore es 1 MiB; el que se usa deja margen a propósito.
  test('el tope elegido deja margen contra el límite real', () {
    expect(topeDelDocumento, lessThan(1048576));
    expect(topeDelDocumento, greaterThan(500000));
  });

  test('un viaje LARGO de verdad entra sin que nadie haga nada', () {
    // Cinco horas a una ventana cada cinco segundos.
    final listo = recortarParaSubir(reporteCon(3600));
    expect(listo.recorte.noEntro, isFalse);
    expect(pesar(listo.reporte), lessThanOrEqualTo(topeDelDocumento));
  });
}
