/// Una carga de combustible, tal como se teclea en la estación.
///
/// Todo lo que hay acá adentro lo escribió una persona parada al lado del
/// surtidor. Nada se calcula ni se deduce: el consumo, el costo por kilómetro
/// y la autonomía salen de mirar dos cargas juntas, al leer. Ver `consumo.dart`.
class Carga {
  final int? id;

  /// Cuándo se cargó, en milisegundos desde la época.
  final int t;

  final double litros;

  /// Lo que salió. Opcional: a veces se carga y no se anota el precio.
  final double? costo;

  /// `UYU` o `USD`. **Cada moneda es un sistema aparte y no se suman nunca**,
  /// ni siquiera para mostrar un total.
  final String moneda;

  /// Lo que marcaba el odómetro **del tablero**, que es lo que se lee ahí.
  /// No es la distancia real: para eso está el factor de neumáticos, que
  /// traduce esto a kilómetros reales.
  final double odoTablero;

  /// **La pieza que hace posible calcular consumo.** Un tanque sólo se sabe
  /// cuánto tiene cuando rebalsa: de lleno a lleno se sabe exactamente cuántos
  /// litros entraron y cuántos kilómetros se hicieron con ellos. Una carga
  /// parcial no cierra una ventana, pero sus litros cuentan en la siguiente.
  final bool tanqueLleno;

  final String? estacion;
  final String? notas;

  const Carga({
    required this.t,
    required this.litros,
    required this.odoTablero,
    this.id,
    this.costo,
    this.moneda = 'UYU',
    this.tanqueLleno = true,
    this.estacion,
    this.notas,
  });

  /// Qué tiene de malo esta carga, o `null` si está bien.
  ///
  /// Devuelve el problema con **palabras**, no un código: el que teclea está en
  /// una estación de servicio con el surtidor esperando.
  String? get problema {
    if (!litros.isFinite || litros <= 0) {
      return 'Los litros tienen que ser un número mayor que cero.';
    }
    if (litros > 200) {
      return 'Doscientos litros no entran en el tanque. Revisá el número.';
    }
    if (!odoTablero.isFinite || odoTablero <= 0) {
      return 'Falta lo que marca el odómetro del tablero.';
    }
    final c = costo;
    if (c != null && (!c.isFinite || c < 0)) {
      return 'El costo no puede ser negativo.';
    }
    if (moneda != 'UYU' && moneda != 'USD') {
      return 'La moneda tiene que ser UYU o USD.';
    }
    return null;
  }

  /// Precio por litro, o `null` si no se anotó el costo. Se calcula, no se
  /// guarda.
  double? get precioPorLitro =>
      costo == null || litros <= 0 ? null : costo! / litros;
}
