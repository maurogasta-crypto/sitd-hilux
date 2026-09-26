import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/cascada.dart';
import 'package:sitd_hilux/features/odometro/fuente.dart';
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

  // `sitd-33`. Sin esto el recuerdo escondía el arreglo: la versión que agrega
  // el permiso que le faltaba a «Normal» iba a seguir arrancando por «Sin
  // notificación» para siempre, sin volver a probarlo nunca.
  group('lo recordado vale para UNA versión', () {
    test('lo que se aprendió con otra versión se ignora', () {
      ModoRecordado(base, sello: 'sitd-32').recordar(ModoGps.sinNotificacion);
      expect(
        ModoRecordado(base, sello: 'sitd-32').modo,
        ModoGps.sinNotificacion,
      );
      expect(ModoRecordado(base, sello: 'sitd-33').modo, isNull);
    });

    test('lo que está guardado HOY en el teléfono se vuelve a probar', () {
      // Es el valor exacto que tiene el Redmi 15: escrito antes de `sitd-33`,
      // sin sello. Tiene que leerse como «no sé», no como «Sin notificación».
      base.escribirAjuste('modo_gps_que_anduvo', 'sinNotificacion');
      expect(recordado.modo, isNull);
      expect(
        escalonesEmpezandoPor(recordado.modo, escalonesPorDefecto).first.modo,
        ModoGps.normal,
        reason: 'el primer viaje después de actualizar vuelve a probar Normal',
      );
    });

    test(
      'y si con la versión nueva vuelve a entregar otro, se aprende de nuevo',
      () {
        base.escribirAjuste('modo_gps_que_anduvo', 'sinNotificacion');
        recordado.recordar(ModoGps.sinNotificacion);
        expect(recordado.modo, ModoGps.sinNotificacion);
        expect(base.leerAjuste('modo_gps_que_anduvo'), contains('@'));
      },
    );

    test('un valor roto no rompe: vacío, con dos arrobas, o sin modo', () {
      for (final roto in ['', '@', 'normal@', 'a@b@c', '@${recordado.sello}']) {
        base.escribirAjuste('modo_gps_que_anduvo', roto);
        expect(recordado.modo, isNull, reason: 'guardado: «$roto»');
      }
    });
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

  _pruebasDelOrdenVivo();
}

/// Lo que se agregó el 2026-09-21, y cubre una falla MEDIDA en el primer
/// viaje real.
///
/// Ese viaje anotó en su bitácora «el modo Sin notificación entregó, el
/// próximo viaje arranca por ahí» y, al reanudarse, volvió a empezar por
/// «Normal» y pagó los noventa segundos de nuevo. La causa: el orden de los
/// escalones se calculaba UNA vez, al abrir la aplicación, y
/// `FuenteEnCascada.escalones` era `final`. Lo aprendido a mitad de sesión no
/// se usaba hasta reiniciar.
///
/// Ahora la cascada recibe una FUNCIÓN y vuelve a preguntar al soltar — o sea
/// entre un viaje y el siguiente. Estas pruebas miran eso desde afuera, por el
/// modo con el que arranca, que es lo que se ve en la pantalla del viaje.
void _pruebasDelOrdenVivo() {
  test('sin preferencia, arranca por el primer escalón', () {
    final c = FuenteEnCascada(construir: (m) => _FuenteMuda());
    expect(c.modo.value, escalonesPorDefecto.first.modo);
  });

  test('con preferencia, arranca por ésa desde el principio', () {
    final c = FuenteEnCascada(
      construir: (m) => _FuenteMuda(),
      modoPreferido: () => ModoGps.receptorDirecto,
    );
    expect(c.modo.value, ModoGps.receptorDirecto);
  });

  test('lo que cambia DESPUÉS de construir se usa al soltar', () async {
    ModoGps? preferido;
    final c = FuenteEnCascada(
      construir: (m) => _FuenteMuda(),
      modoPreferido: () => preferido,
    );
    expect(c.modo.value, escalonesPorDefecto.first.modo);

    // Esto es lo que hacía la cascada vieja y no se usaba: aprender a mitad
    // de sesión.
    preferido = ModoGps.sinNotificacion;
    await c.detener();

    expect(
      c.modo.value,
      ModoGps.sinNotificacion,
      reason: 'el viaje siguiente tiene que empezar por el modo que entregó',
    );
  });

  test(
    'un modo preferido que no existe no rompe: queda el orden de siempre',
    () {
      final c = FuenteEnCascada(
        construir: (m) => _FuenteMuda(),
        modoPreferido: () => null,
      );
      expect(c.modo.value, escalonesPorDefecto.first.modo);
    },
  );

  test('la cascada NUNCA pierde escalones al reordenar', () {
    for (final m in ModoGps.values) {
      final e = escalonesEmpezandoPor(m, escalonesPorDefecto);
      expect(
        e.length,
        escalonesPorDefecto.length,
        reason: 'reordenar por $m perdió un escalón',
      );
      expect(e.map((x) => x.modo).toSet(), {
        for (final d in escalonesPorDefecto) d.modo,
      });
    }
  });
}

/// Una fuente que no entrega nunca. Alcanza para mirar con qué modo arranca
/// la cascada, que es lo único que prueban los casos de arriba.
class _FuenteMuda implements FuenteDeMuestras {
  final _c = StreamController<Lectura>();

  @override
  Stream<Lectura> get lecturas => _c.stream;

  @override
  Future<Disponibilidad> preparar() async => Disponibilidad.listo;

  @override
  Future<void> detener() async => _c.close();
}
