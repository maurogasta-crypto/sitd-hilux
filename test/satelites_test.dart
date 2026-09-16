import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/sensores/satelites.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('prueba/satelites');
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void responder(Object? Function(MethodCall) f) =>
      mensajero.setMockMethodCallHandler(canal, (c) async => f(c));

  tearDown(() => mensajero.setMockMethodCallHandler(canal, null));

  Map<String, dynamic> respuesta({
    int vistos = 0,
    int usados = 0,
    double mejor = 0,
    bool fijo = false,
    String evento = 'contando satélites',
  }) => {
    'enganchado': true,
    'vistos': vistos,
    'usados': usados,
    'mejorCn0': mejor,
    'cn0': <double>[mejor],
    'evento': evento,
    'msDelUltimo': 120,
    'huboPrimerFijado': fijo,
  };

  group('el veredicto, que es para lo que existe esta pieza', () {
    test('sin canal nativo lo dice y no se hace el que sabe', () {
      const e = EstadoSatelites();
      expect(e.veredicto, contains('no contestó'));
      expect(e.disponible, isFalse);
    });

    test('CERO satélites vistos: no es paciencia, es la antena', () {
      const e = EstadoSatelites(disponible: true, enganchado: true, vistos: 0);
      expect(e.veredicto, contains('NO ve un solo satélite'));
      expect(e.veredicto, contains('Ningún cambio en esta aplicación'));
    });

    test(
      've satélites y no usa ninguno: arranque en frío, hay que esperar',
      () {
        const e = EstadoSatelites(
          disponible: true,
          enganchado: true,
          vistos: 11,
          usados: 0,
        );
        expect(e.veredicto, contains('Ve 11 satélites'));
        expect(e.veredicto, contains('efeméride vieja'));
        expect(e.veredicto, contains('QUIETO'));
      },
    );

    test('usa satélites: está fijando', () {
      const e = EstadoSatelites(
        disponible: true,
        enganchado: true,
        vistos: 11,
        usados: 6,
      );
      expect(e.veredicto, contains('usa 6'));
      expect(e.veredicto, contains('fijando'));
    });

    test('si alguna vez fijó, deja de ser un problema de antena', () {
      const e = EstadoSatelites(
        disponible: true,
        enganchado: true,
        vistos: 0,
        huboPrimerFijado: true,
      );
      expect(e.veredicto, contains('ya fijó'));
    });
  });

  test('arrancar lee el estado y lo traduce', () async {
    var arranco = false;
    responder((c) {
      if (c.method == 'arrancar') {
        arranco = true;
        return true;
      }
      return respuesta(vistos: 9, usados: 4, mejor: 31.5, evento: 'contando');
    });

    final e = await Satelites(canal: canal).arrancar();

    expect(arranco, isTrue);
    expect(e.disponible, isTrue);
    expect(e.vistos, 9);
    expect(e.usados, 4);
    expect(e.mejorCn0, 31.5);
    expect(e.cn0, [31.5]);
    expect(e.evento, 'contando');
  });

  test('si el sistema no deja enganchar, no se rompe nada', () async {
    responder((c) => c.method == 'arrancar' ? false : respuesta());
    final e = await Satelites(canal: canal).arrancar();
    // No arrancó, así que `leer` devuelve el estado vacío y la pantalla dice
    // «no contestó» en vez de mostrar ceros que parecerían medidos.
    expect(e.disponible, isFalse);
  });

  test('sin canal nativo devuelve no disponible y NO lanza', () async {
    // Sin handler puesto, el mensajero contesta que el plugin no existe.
    final s = Satelites(canal: const MethodChannel('prueba/no-existe'));
    final e = await s.arrancar();
    expect(e.disponible, isFalse);
    expect(e.falla, contains('no está'));
    // Y leer tampoco lanza.
    expect((await s.leer()).disponible, isFalse);
  });

  test('una excepción del lado nativo se devuelve como falla', () async {
    responder((c) {
      if (c.method == 'arrancar') return true;
      throw PlatformException(code: 'roto');
    });
    final e = await Satelites(canal: canal).arrancar();
    expect(e.disponible, isFalse);
    expect(e.falla, contains('roto'));
  });

  test('leer antes de arrancar no habla con el sistema', () async {
    var llamadas = 0;
    responder((c) {
      llamadas++;
      return respuesta();
    });
    final e = await Satelites(canal: canal).leer();
    expect(llamadas, 0);
    expect(e.disponible, isFalse);
  });

  test('detener sólo habla si había arrancado', () async {
    var detenciones = 0;
    responder((c) {
      if (c.method == 'detener') detenciones++;
      if (c.method == 'arrancar') return true;
      return respuesta();
    });
    final s = Satelites(canal: canal);

    await s.detener();
    expect(detenciones, 0);

    await s.arrancar();
    await s.detener();
    expect(detenciones, 1);

    // Y dos veces seguidas no vuelve a hablar.
    await s.detener();
    expect(detenciones, 1);
  });

  test('lo que viaja al reporte no trae la falla del sistema', () async {
    const e = EstadoSatelites(disponible: true, vistos: 3, falla: 'texto feo');
    expect(e.aMapa().containsKey('falla'), isFalse);
    expect(e.aMapa()['vistos'], 3);
  });
}
