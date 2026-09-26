import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/bitacora.dart';
import 'package:sitd_hilux/main.dart';

/// El banco del enganche de errores (`sitd-33`).
///
/// Existe porque el modo «Normal» del GPS no entregó nunca en el Redmi 15 y
/// nunca dijo por qué: el error se iba por `FlutterError.reportError`, que por
/// defecto sólo se imprime en una consola que nadie mira. Lo que se prueba es
/// que ahora llegue a la bitácora, con lo que hace falta para saber QUÉ falló.
void main() {
  late FlutterExceptionHandler? delBanco;

  setUp(() {
    bitacora.limpiar();
    // El banco de Flutter registra cada error como una prueba fallida. Se
    // cambia por uno mudo mientras dura la prueba y se devuelve después: lo
    // que se prueba es que el nuestro ANOTE, no que el de siempre imprima.
    delBanco = FlutterError.onError;
    FlutterError.onError = (_) {};
  });

  tearDown(() => FlutterError.onError = delBanco);

  List<String> textos() => [
    for (final a in bitacora.aMapa()) a['texto'] as String,
  ];

  // Es exactamente lo que dice Flutter cuando un complemento falla al abrir
  // un canal de eventos — el caso del GPS.
  FlutterErrorDetails fallaDelCanal() => FlutterErrorDetails(
    exception: Exception(
      'SecurityException: Neither user 10284 nor current process has '
      'android.permission.WAKE_LOCK.',
    ),
    context: ErrorDescription(
      'while activating platform stream on channel '
      'flutter.baseflow.com/geolocator_updates_android',
    ),
  );

  test('un error de canal llega a la bitácora, con el nombre del canal', () {
    escucharErroresDelSistema();
    FlutterError.reportError(fallaDelCanal());
    final t = textos();
    expect(t, hasLength(1));
    // El nombre del canal es lo que dice qué complemento fue.
    expect(t.single, contains('geolocator_updates_android'));
    expect(t.single, contains('WAKE_LOCK'));
  });

  test('el mismo error repetido deja UNA línea, no trescientas', () {
    // Un error de dibujo se repite en cada cuadro: sin esto se llevaría
    // puesto el anillo entero en cinco segundos.
    escucharErroresDelSistema();
    for (var i = 0; i < 50; i++) {
      FlutterError.reportError(fallaDelCanal());
    }
    expect(textos(), hasLength(1));
  });

  test('y sigue llamando al que estaba: agrega un destino, no saca otro', () {
    var llamado = 0;
    FlutterError.onError = (_) => llamado++;
    escucharErroresDelSistema();
    FlutterError.reportError(fallaDelCanal());
    expect(llamado, 1);
  });

  test('un error largo se recorta, y se dice que se recortó', () {
    final largo = 'x' * 1000;
    final r = recortarError(largo);
    expect(r.length, 301);
    expect(r, endsWith('…'));
    expect(recortarError('corto'), 'corto');
  });

  test('los saltos de línea de una pila se vuelven un solo renglón', () {
    expect(recortarError('uno\n   dos\t\ttres\n'), 'uno dos tres');
  });

  test('sin contexto no inventa uno', () {
    final t = textoDeError(FlutterErrorDetails(exception: Exception('algo')));
    expect(t, startsWith('Error del sistema: '));
    expect(t, isNot(contains('()')));
  });
}
