import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/cascada.dart';
import 'package:sitd_hilux/features/odometro/fuente_gps.dart';
import 'package:sitd_hilux/features/odometro/modo_recordado.dart';

void main() {
  late Base base;
  late ModoRecordado recordado;

  setUp(() {
    base = Base.abrir(':memory:');
    recordado = ModoRecordado(base);
  });

  tearDown(() => base.cerrar());

  test('al principio no sabe nada, y eso no es un error', () {
    expect(recordado.modo, isNull);
  });

  test('recuerda el modo que entregó, y sobrevive a cerrar la aplicación', () {
    recordado.recordar(ModoGps.sinNotificacion);
    expect(recordado.modo, ModoGps.sinNotificacion);

    // Otra corrida sobre la misma base.
    expect(ModoRecordado(base).modo, ModoGps.sinNotificacion);
  });

  test('un nombre que ya no existe se ignora en vez de romper', () {
    base.escribirAjuste('modo_gps_que_anduvo', 'modoQueSeRenombro');
    expect(recordado.modo, isNull);
  });

  test('olvidar lo deja como al principio', () {
    recordado.recordar(ModoGps.receptorDirecto);
    recordado.olvidar();
    expect(recordado.modo, isNull);
  });

  group('el reordenamiento de los escalones', () {
    test('sin nada recordado, el orden es el de siempre', () {
      final e = escalonesEmpezandoPor(null, escalonesPorDefecto);
      expect(e, same(escalonesPorDefecto));
    });

    test('el recordado pasa al frente y NO se pierde ninguno', () {
      final e = escalonesEmpezandoPor(
        ModoGps.receptorDirecto,
        escalonesPorDefecto,
      );
      expect(e.map((x) => x.modo).toList(), [
        ModoGps.receptorDirecto,
        ModoGps.normal,
        ModoGps.sinNotificacion,
      ]);
      // La red sigue entera: si el recordado deja de andar, hay a dónde bajar.
      expect(e.length, escalonesPorDefecto.length);
    });

    test('si el recordado YA era el primero, no se toca nada', () {
      final e = escalonesEmpezandoPor(ModoGps.normal, escalonesPorDefecto);
      expect(e, same(escalonesPorDefecto));
    });

    test('cada escalón conserva su paciencia al reordenarse', () {
      final e = escalonesEmpezandoPor(
        ModoGps.sinNotificacion,
        escalonesPorDefecto,
      );
      final original = escalonesPorDefecto.firstWhere(
        (x) => x.modo == ModoGps.sinNotificacion,
      );
      expect(e.first.paciencia, original.paciencia);
    });
  });

  // El caso real del 2026-09-19: el viaje esperó los 90 s de `normal` sin
  // recibir nada, bajó a `sinNotificacion` y midió 105 muestras. Sin esto,
  // el viaje siguiente vuelve a perder los mismos 90 s.
  test('el viaje siguiente arranca por donde el anterior entregó', () {
    recordado.recordar(ModoGps.sinNotificacion);
    final e = escalonesEmpezandoPor(recordado.modo, escalonesPorDefecto);
    expect(e.first.modo, ModoGps.sinNotificacion);
  });

  test('recordar el mismo modo dos veces no vuelve a escribir', () {
    recordado.recordar(ModoGps.sinNotificacion);
    final antes = base.leerAjuste('modo_gps_que_anduvo');
    recordado.recordar(ModoGps.sinNotificacion);
    expect(base.leerAjuste('modo_gps_que_anduvo'), antes);
  });
}
