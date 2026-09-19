import '../../core/bitacora.dart';
import '../../core/db/base.dart';
import 'cascada.dart';
import 'fuente_gps.dart';

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
class ModoRecordado {
  final Base base;

  static const String _clave = 'modo_gps_que_anduvo';

  ModoRecordado(this.base);

  /// El modo con el que conviene arrancar, o `null` si todavía no se sabe.
  ModoGps? get modo {
    final guardado = base.leerAjuste(_clave);
    if (guardado == null) return null;
    for (final m in ModoGps.values) {
      if (m.name == guardado) return m;
    }
    // Un nombre que ya no existe —renombrado entre tandas— se ignora en vez
    // de romper: arrancar por el primer escalón siempre es seguro.
    return null;
  }

  /// Anota el modo que entregó. Sólo escribe cuando cambia: un INSERT por
  /// viaje para guardar lo mismo no aporta nada.
  void recordar(ModoGps m) {
    if (modo == m) return;
    base.escribirAjuste(_clave, m.name);
    bitacora.anotar(
      Origen.gps,
      'El modo ${nombreDeModo(m)} entregó. El próximo viaje arranca por ahí '
      'en vez de esperar los noventa segundos del primer escalón.',
    );
  }

  void olvidar() => base.escribirAjuste(_clave, '');
}

/// Los escalones reordenados para que [primero] quede adelante.
///
/// **No se saca ninguno**: si el recordado deja de andar, la cascada sigue
/// teniendo a dónde bajar. Lo único que cambia es por cuál empieza.
List<Escalon> escalonesEmpezandoPor(ModoGps? primero, List<Escalon> todos) {
  if (primero == null) return todos;
  final i = todos.indexWhere((e) => e.modo == primero);
  if (i <= 0) return todos;
  return [todos[i], ...todos.where((e) => e.modo != primero)];
}
