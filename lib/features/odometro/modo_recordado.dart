import '../../core/bitacora.dart';
import '../../core/db/base.dart';
import '../../core/version.dart';
import 'fuente_gps.dart';

// `escalonesEmpezandoPor` vive en `cascada.dart` —acá sería un import
// circular— y se reexporta para que quien ya la pedía a este archivo no tenga
// que cambiar nada.
export 'cascada.dart' show escalonesEmpezandoPor;

/// Qué modo de pedir posiciones funcionó la última vez.
///
/// **Existe por dos costos concretos de la cascada, medidos en un viaje real
/// el 2026-09-19.** Ese viaje arrancó en `normal`, esperó los noventa segundos
/// completos sin recibir una sola posición, bajó a `sinNotificacion` y midió
/// perfecto: 105 muestras, ninguna descartada, 3,79 m de precisión.
///
/// O sea que en ESTE teléfono el modo `normal` no entrega, y la cascada lo
/// vuelve a descubrir en cada viaje. Eso son:
///
///  - **noventa segundos de cada viaje sin medir**, que en un tramo corto es
///    el tramo entero;
///  - y un cartel de aviso en cada viaje por algo que ya se sabe.
///
/// Así que el modo que entregó se guarda, y el próximo viaje arranca por ahí.
/// **La cascada no se saca**: si el modo recordado deja de andar, baja igual —
/// y el orden de los escalones sigue siendo el mismo, así que un teléfono
/// donde `normal` funcione lo sigue usando.
///
/// ## Y lo recordado vale para UNA versión (`sitd-33`)
///
/// Se guarda como `modo@sello`, y con otro sello se ignora. **Sin eso, el
/// recuerdo escondía el arreglo:** `sitd-33` agrega el permiso que
/// probablemente le faltaba al modo `normal`, y la aplicación iba a seguir
/// arrancando por `sinNotificacion` para siempre, sin volver a probar nunca el
/// único modo que mide con la pantalla apagada. Lo que se aprendió con una
/// versión no vale para la siguiente, porque la siguiente puede haber
/// arreglado justo lo que fallaba.
///
/// La contra está aceptada y es chica: el primer viaje después de cada
/// actualización vuelve a pagar los noventa segundos si `normal` sigue sin
/// andar — una vez por versión, no una por viaje.
class ModoRecordado {
  final Base base;

  static const String _clave = 'modo_gps_que_anduvo';

  /// El sello contra el que se compara. Es un parámetro y no se lee de
  /// [selloApp] adentro para que el banco pueda simular una actualización.
  final String sello;

  ModoRecordado(this.base, {this.sello = selloApp});

  /// El modo con el que conviene arrancar, o `null` si todavía no se sabe
  /// —o si lo que se sabe se aprendió con otra versión—.
  ModoGps? get modo {
    final guardado = base.leerAjuste(_clave);
    if (guardado == null || guardado.isEmpty) return null;
    // Un valor sin «@» es de antes de `sitd-33`: de otra versión, por
    // definición. Se ignora igual que uno con otro sello.
    final partes = guardado.split('@');
    if (partes.length != 2 || partes[1] != sello) return null;
    for (final m in ModoGps.values) {
      if (m.name == partes[0]) return m;
    }
    // Un nombre que ya no existe —renombrado entre tandas— se ignora en vez
    // de romper: arrancar por el primer escalón siempre es seguro.
    return null;
  }

  /// Anota el modo que entregó. Sólo escribe cuando cambia: un INSERT por
  /// viaje para guardar lo mismo no aporta nada.
  void recordar(ModoGps m) {
    if (modo == m) return;
    base.escribirAjuste(_clave, '${m.name}@$sello');
    bitacora.anotar(
      Origen.gps,
      'El modo ${nombreDeModo(m)} entregó. El próximo viaje arranca por ahí '
      'en vez de esperar los noventa segundos del primer escalón.',
    );
  }

  void olvidar() => base.escribirAjuste(_clave, '');
}

// `escalonesEmpezandoPor` se mudó a `cascada.dart` el 2026-09-21 y se
// reexporta desde acá para que nada de lo que ya la importaba cambie.
//
// Se mudó porque la cascada tiene que poder reordenarse SOLA al empezar cada
// viaje, y este archivo ya importa a aquél: dejarla acá era un import
// circular. Es la misma función, en el lugar donde se usa.
