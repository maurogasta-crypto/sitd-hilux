import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/nube/credencial.dart';
import 'package:sitd_hilux/features/nube/sesion.dart';

/// El banco de la sesión de la nube.
///
/// Lo que se prueba acá es una sola cosa y es la que importa: **que la
/// contraseña deje de vivir en el teléfono en cuanto hay un `refreshToken`**.
/// Todo lo demás —renovar contra Firebase, que el token sirva— necesita red y
/// se comprueba andando; esto comprueba lo que se puede comprobar sin salir,
/// que es justo donde está el riesgo de equivocarse en silencio.
void main() {
  late Base base;
  late GuardaDeSesion sesion;
  late GuardaDeCredencial guarda;

  setUp(() {
    base = Base.abrir(':memory:');
    sesion = GuardaDeSesion(base);
    guarda = GuardaDeCredencial(base);
  });

  tearDown(() => base.cerrar());

  group('el token', () {
    test('al principio no hay, y eso no es un error', () {
      expect(sesion.token, isNull);
      expect(sesion.hay, isFalse);
    });

    test('se guarda y se lee igual', () {
      sesion.guardar('un-token-de-prueba');
      expect(sesion.token, 'un-token-de-prueba');
      expect(sesion.hay, isTrue);
    });

    test('olvidarlo deja el estado como al principio', () {
      sesion.guardar('un-token-de-prueba');
      sesion.olvidar();
      expect(sesion.token, isNull);
      expect(sesion.hay, isFalse);
    });

    test('vacío cuenta como que no hay: no se reintenta contra la nada', () {
      sesion.guardar('');
      expect(sesion.hay, isFalse);
    });
  });

  group('la contraseña se borra y el resto queda', () {
    const pegado =
        '{"proyecto":"p","apiKey":"k","mail":"m@e.invalido","clave":"secreta"}';

    test('antes de borrarla, la configuración está completa', () {
      expect(guarda.guardar(pegado), isNull);
      expect(guarda.credencial!.completa, isTrue);
    });

    test('olvidarClave saca SÓLO la contraseña', () {
      guarda.guardar(pegado);
      guarda.olvidarClave();
      final c = guarda.credencial!;
      expect(c.clave, isEmpty);
      expect(c.proyecto, 'p');
      expect(c.apiKey, 'k');
      expect(c.mail, 'm@e.invalido');
    });

    test('sin contraseña ya no está «completa», pero sí identifica', () {
      guarda.guardar(pegado);
      guarda.olvidarClave();
      final c = guarda.credencial!;
      expect(c.completa, isFalse);
      expect(c.identificaProyecto, isTrue);
    });

    // La que de verdad importa: que el valor no quede en el texto guardado.
    // Comprobarlo sobre el CRUDO y no sobre el objeto, porque lo que se lleva
    // quien saque el archivo del teléfono es el crudo.
    test('la contraseña no queda en lo que se guardó', () {
      guarda.guardar(pegado);
      guarda.olvidarClave();
      expect(base.leerAjuste('nube_config'), isNot(contains('secreta')));
    });

    test('olvidarClave sin nada configurado no explota', () {
      expect(guarda.olvidarClave, returnsNormally);
    });

    test('el resumen que se muestra nunca trae la contraseña', () {
      guarda.guardar(pegado);
      expect(guarda.credencial!.resumen, isNot(contains('secreta')));
    });
  });
}
