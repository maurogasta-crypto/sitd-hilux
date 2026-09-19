import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/features/odometro/cascada.dart';
import 'package:sitd_hilux/features/odometro/fuente.dart';
import 'package:sitd_hilux/features/odometro/fuente_gps.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/permisos/avisos.dart';

/// Una fuente de mentira que no entrega nada hasta que se le dice.
class FuenteFalsa implements FuenteDeMuestras {
  final ModoGps modo;
  final control = StreamController<Lectura>();
  int detenida = 0;
  Disponibilidad respuesta;

  FuenteFalsa(this.modo, {this.respuesta = Disponibilidad.listo});

  @override
  Stream<Lectura> get lecturas => control.stream;

  @override
  Future<Disponibilidad> preparar() async => respuesta;

  @override
  Future<void> detener() async {
    detenida++;
    if (!control.isClosed) await control.close();
  }
}

Muestra muestra(int t) =>
    Muestra(t: t, lat: -34.9, lon: -56.2, velocidad: 10, precision: 5);

/// Escalones cortos: el banco no espera noventa segundos de verdad.
const rapidos = [
  Escalon(ModoGps.normal, Duration(milliseconds: 40)),
  Escalon(ModoGps.sinNotificacion, Duration(milliseconds: 40)),
  Escalon(ModoGps.receptorDirecto, Duration(milliseconds: 40)),
];

void main() {
  late Map<ModoGps, FuenteFalsa> hechas;
  FuenteEnCascada armar({
    List<Escalon> escalones = rapidos,
    PedirAviso? aviso,
  }) {
    hechas = {};
    return FuenteEnCascada(
      escalones: escalones,
      construir: (m) => hechas[m] = FuenteFalsa(m),
      pedirAviso: aviso ?? () async => EstadoAviso.concedido,
    );
  }

  test('los escalones de verdad van del modo bueno al peor', () {
    expect(escalonesPorDefecto.map((e) => e.modo).toList(), [
      ModoGps.normal,
      ModoGps.sinNotificacion,
      ModoGps.receptorDirecto,
    ]);
    // Al primero se le da tiempo de fijar satélites: bajarlo antes sería
    // abandonar el único modo que mide con la pantalla apagada.
    expect(
      escalonesPorDefecto.first.paciencia.inSeconds,
      greaterThanOrEqualTo(60),
    );
  });

  test('si el primer modo entrega, la cascada se queda ahí', () async {
    final c = armar();
    final recibidas = <Lectura>[];
    final sub = c.lecturas.listen(recibidas.add);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    hechas[ModoGps.normal]!.control.add(Lectura(muestra(1)));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(c.modo.value, ModoGps.normal);
    expect(c.entrego, isTrue);
    expect(hechas.keys, [ModoGps.normal]);
    expect(recibidas.length, 1);
    await sub.cancel();
  });

  test(
    'una posición sin Doppler también cuenta como que el receptor habló',
    () async {
      final c = armar();
      final sub = c.lecturas.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      hechas[ModoGps.normal]!.control.add(const Lectura(null));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(c.modo.value, ModoGps.normal);
      await sub.cancel();
    },
  );

  test('si nadie entrega, baja hasta el último y se queda', () async {
    final c = armar();
    final sub = c.lecturas.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(c.modo.value, ModoGps.receptorDirecto);
    expect(c.probados, [
      ModoGps.normal,
      ModoGps.sinNotificacion,
      ModoGps.receptorDirecto,
    ]);
    // Cada escalón que se abandona se suelta: no quedan dos suscripciones
    // contra el receptor del teléfono.
    expect(hechas[ModoGps.normal]!.detenida, 1);
    expect(hechas[ModoGps.sinNotificacion]!.detenida, 1);
    await sub.cancel();
  });

  test('lo que entrega el modo al que se bajó llega al que escucha', () async {
    final c = armar();
    final recibidas = <Lectura>[];
    final sub = c.lecturas.listen(recibidas.add);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(c.modo.value, ModoGps.sinNotificacion);
    hechas[ModoGps.sinNotificacion]!.control.add(Lectura(muestra(2)));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(recibidas.length, 1);
    expect(recibidas.first.muestra?.t, 2);
    // Entregó, así que la cascada dejó de moverse.
    expect(c.modo.value, ModoGps.sinNotificacion);
    await sub.cancel();
  });

  test(
    'un error en un modo intermedio baja de escalón y no se propaga',
    () async {
      final c = armar();
      Object? error;
      final sub = c.lecturas.listen((_) {}, onError: (Object e) => error = e);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      hechas[ModoGps.normal]!.control.addError(StateError('sin servicio'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(error, isNull);
      expect(c.modo.value, ModoGps.sinNotificacion);
      await sub.cancel();
    },
  );

  test('un error en el último modo sí se propaga: es la respuesta', () async {
    final c = armar();
    Object? error;
    final sub = c.lecturas.listen((_) {}, onError: (Object e) => error = e);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.modo.value, ModoGps.receptorDirecto);
    hechas[ModoGps.receptorDirecto]!.control.addError(StateError('nada'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(error, isA<StateError>());
    await sub.cancel();
  });

  test('que un modo cierre el stream se trata como silencio', () async {
    final c = armar();
    final sub = c.lecturas.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await hechas[ModoGps.normal]!.control.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(c.modo.value, ModoGps.sinNotificacion);
    await sub.cancel();
  });

  test('cancelar mientras baja no abre el modo siguiente', () async {
    final c = armar();
    final sub = c.lecturas.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    final abiertos = hechas.length;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(hechas.length, abiertos);
    // Y vuelve al primer escalón: el próximo viaje pide el modo bueno, no
    // hereda el parche del anterior.
    expect(c.modo.value, ModoGps.normal);
    expect(c.entrego, isFalse);
  });

  test(
    'detener suelta el escalón puesto y deja la cascada como nueva',
    () async {
      final c = armar();
      final sub = c.lecturas.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.modo.value, ModoGps.sinNotificacion);
      await sub.cancel();
      await c.detener();

      expect(c.modo.value, ModoGps.normal);
      expect(c.probados, [ModoGps.normal]);
    },
  );

  test(
    'preparar pide el permiso de notificaciones y anota cómo quedó',
    () async {
      var pedido = 0;
      final c = armar(
        aviso: () async {
          pedido++;
          return EstadoAviso.negadoParaSiempre;
        },
      );
      expect(c.aviso.value, isNull);

      final d = await c.preparar();

      expect(pedido, 1);
      expect(c.aviso.value, EstadoAviso.negadoParaSiempre);
      // Que no haya cartel NO impide medir: eso sería cambiar un problema de
      // visibilidad por uno de odometría.
      expect(d.puedeArrancar, isTrue);
    },
  );

  test('el permiso se pide una vez por viaje, no una por escalón', () async {
    var pedido = 0;
    final c = armar(
      aviso: () async {
        pedido++;
        return EstadoAviso.concedido;
      },
    );
    await c.preparar();
    final sub = c.lecturas.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(c.modo.value, ModoGps.receptorDirecto);
    expect(pedido, 1);
    await sub.cancel();
  });

  test('avisa cuál fue el modo que entregó, para poder recordarlo', () async {
    final anotados = <ModoGps>[];
    hechas = {};
    final c = FuenteEnCascada(
      escalones: rapidos,
      construir: (m) => hechas[m] = FuenteFalsa(m),
      pedirAviso: () async => EstadoAviso.concedido,
      alEntregar: anotados.add,
    );
    final sub = c.lecturas.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 60));
    hechas[ModoGps.sinNotificacion]!.control.add(Lectura(muestra(1)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(anotados, [ModoGps.sinNotificacion]);

    // Y avisa UNA vez: lo que importa es cuál entregó, no cuántas veces.
    hechas[ModoGps.sinNotificacion]!.control.add(Lectura(muestra(2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(anotados.length, 1);
    await sub.cancel();
  });

  test('cada modo tiene su nombre para la pantalla', () {
    expect(nombreDeModo(ModoGps.normal), 'Normal');
    expect(nombreDeModo(ModoGps.sinNotificacion), 'Sin notificación');
    expect(nombreDeModo(ModoGps.receptorDirecto), 'Receptor directo');
    for (final e in EstadoAviso.values) {
      expect(textoDeAviso(e), isNotEmpty);
    }
  });
}
