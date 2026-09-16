import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/pantalla_despierta.dart';

void main() {
  late Base base;
  late List<bool> pedidos;
  late PantallaDespierta despierta;

  setUp(() {
    base = Base.abrir(':memory:');
    pedidos = [];
    despierta = PantallaDespierta(
      base,
      aplicar: ({required bool encendida}) async => pedidos.add(encendida),
    );
  });

  tearDown(() => base.cerrar());

  test('viene encendida: el caso normal es la camioneta enchufada', () {
    expect(despierta.preferida, isTrue);
  });

  test('la preferencia sobrevive a cerrar la aplicación', () {
    despierta.preferida = false;
    expect(PantallaDespierta(base).preferida, isFalse);
    despierta.preferida = true;
    expect(PantallaDespierta(base).preferida, isTrue);
  });

  test(
    'midiendo y con la preferencia puesta, la pantalla queda despierta',
    () async {
      await despierta.segun(midiendo: true);
      expect(pedidos, [true]);
    },
  );

  // Son dos cosas distintas: la preferencia dice «cuando mida», no «siempre».
  // Sin esto, el teléfono quedaría despierto para siempre después del primer
  // viaje, al sol y enchufado.
  test(
    'sin viaje no se deja el teléfono despierto, aunque esté preferido',
    () async {
      await despierta.segun(midiendo: false);
      expect(pedidos, [false]);
    },
  );

  test('con la preferencia apagada, ni midiendo', () async {
    despierta.preferida = false;
    await despierta.segun(midiendo: true);
    expect(pedidos, [false]);
  });

  // Es una comodidad, no una pieza de la medición: si el sistema no deja, el
  // viaje sigue.
  test('si el sistema no deja, no tira la aplicación abajo', () async {
    final rota = PantallaDespierta(
      base,
      aplicar: ({required bool encendida}) async =>
          throw StateError('sin permiso'),
    );
    await expectLater(rota.segun(midiendo: true), completes);
  });
}
