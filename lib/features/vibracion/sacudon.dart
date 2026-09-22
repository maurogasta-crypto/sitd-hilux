/// Una lectura del acelerómetro, **sin depender del complemento**.
///
/// ## Por qué está en su propio archivo
///
/// Es el mismo reparto que el GPS ya tenía: `Muestra` vive sola y
/// `fuente_gps.dart` es el único que importa `geolocator`. Acá estaba todo
/// junto, y el día que apareció código puro que necesitaba un `Sacudon`
/// —`calidad.dart`, 2026-09-22— ese código quedó arrastrando `sensors_plus`
/// detrás, o sea que dejaba de poder correrse con `dart` a secas.
///
/// La regla, que vale para los dos sensores: **el tipo del dato no conoce al
/// complemento que lo produce.**
library;

/// Se guarda el **módulo** y no los tres ejes: no se sabe cómo quedó puesto el
/// teléfono en la cabina, y con un solo eje el mismo defecto daría números
/// distintos según cómo lo colgaron ese día.
class Sacudon {
  /// Milisegundos desde la época. Es lo que usa todo el circuito de vibración
  /// y alcanza: una ventana dura cinco segundos.
  final int t;

  final double magnitud;

  /// El MISMO instante en microsegundos, para lo único que lo necesita: medir
  /// la regularidad del muestreo.
  ///
  /// **A 50 Hz no hace falta y arriba de 200 Hz es imprescindible.** Con el
  /// período pedido en `fastest`, un teléfono puede entregar cada 2,5 ms; un
  /// sello redondeado al milisegundo lo convierte en 2 o en 3, y ese redondeo
  /// solo se vería como un 50 % de irregularidad que **no existe**. El
  /// instrumento estaría midiendo su propia regla en vez del sensor. Hay una
  /// prueba que compara las dos formas sobre la misma tanda perfecta.
  ///
  /// Por defecto se deduce de [t], que es lo correcto para una fuente de
  /// mentira del banco: ahí los instantes son exactos por construcción.
  final int tMicro;

  const Sacudon(this.t, this.magnitud, {int? micros})
    : tMicro = micros ?? t * 1000;
}
