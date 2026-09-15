import 'muestra.dart';

/// Cálculo del factor de corrección del odómetro de fábrica.
///
/// **La dirección importa y es contraintuitiva.** El GPS ya mide la distancia
/// real: no sabe ni le importa qué neumático está puesto. El que miente es el
/// odómetro del tablero, que cuenta vueltas de rueda y las multiplica por la
/// circunferencia que traía de fábrica.
///
///     km_tablero = km_real × (C_original / C_nuevo)
///     km_real    = km_tablero × k,   con  k = C_nuevo / C_original
///
/// Con neumáticos más grandes que los originales, `k > 1` y el tablero
/// **subestima**. El factor no se aplica nunca a la odometría GPS: sirve para
/// traducir lo que se lee en el tablero al cargar combustible.
///
/// Y no se configura a mano. Calcularlo desde la medida del neumático sale
/// mal: el radio bajo carga es un 2-4 % menor que el libre, y varía con la
/// presión y el peso. Se aprende de los datos.
class Factor {
  /// El factor propiamente dicho.
  final double k;

  /// Cuántos pares intervinieron.
  final int pares;

  /// Dispersión relativa de los cocientes individuales (desviación absoluta
  /// mediana sobre la mediana). Por encima de ~0,03 el factor no es de fiar:
  /// suele indicar odómetros mal anotados.
  final double dispersion;

  const Factor({
    required this.k,
    required this.pares,
    required this.dispersion,
  });

  /// Convierte una lectura del tablero a kilómetros reales.
  double aReal(double kmTablero) => kmTablero * k;

  /// Convierte kilómetros reales a lo que va a marcar el tablero.
  double aTablero(double kmReales) => kmReales / k;

  /// Cuánto se desvía el tablero, en porcentaje. Positivo = el tablero marca
  /// de menos.
  double get errorPorcentual => (k - 1.0) * 100.0;
}

/// Sólo se usan tramos largos: en uno corto, el error de leer el odómetro
/// —que avanza de a 1 km— domina sobre lo que se quiere medir.
const double kmMinimosPorPar = 20.0;

/// Factor por mediana de los cocientes.
///
/// Se prefiere a los mínimos cuadrados porque es robusto: un solo odómetro mal
/// anotado no lo mueve. Con pocos pares —que es el caso real durante meses—
/// esa diferencia es la que importa.
///
/// Devuelve `null` si no hay pares utilizables.
Factor? factorRobusto(List<ParCalibracion> pares) {
  final cocientes = <double>[];
  for (final p in pares) {
    if (p.kmTablero < kmMinimosPorPar) continue;
    if (p.kmGps <= 0 || !p.kmGps.isFinite || !p.kmTablero.isFinite) continue;
    cocientes.add(p.kmGps / p.kmTablero);
  }
  if (cocientes.isEmpty) return null;

  cocientes.sort();
  final k = _mediana(cocientes);
  final desviaciones = cocientes.map((c) => (c - k).abs()).toList()..sort();
  final mad = _mediana(desviaciones);

  return Factor(
    k: k,
    pares: cocientes.length,
    dispersion: k == 0 ? 0 : mad / k,
  );
}

/// Factor por mínimos cuadrados con la recta forzada por el origen.
///
/// Está para comparar contra [factorRobusto], no para reemplazarlo: cuando los
/// dos dan lo mismo, el conjunto de datos está limpio.
Factor? factorMinimosCuadrados(List<ParCalibracion> pares) {
  double sxy = 0, sxx = 0;
  int n = 0;
  for (final p in pares) {
    if (p.kmTablero < kmMinimosPorPar) continue;
    if (p.kmGps <= 0 || !p.kmGps.isFinite || !p.kmTablero.isFinite) continue;
    sxy += p.kmTablero * p.kmGps;
    sxx += p.kmTablero * p.kmTablero;
    n++;
  }
  if (n == 0 || sxx == 0) return null;
  return Factor(k: sxy / sxx, pares: n, dispersion: 0);
}

double _mediana(List<double> ordenados) {
  final n = ordenados.length;
  if (n.isOdd) return ordenados[n ~/ 2];
  return (ordenados[n ~/ 2 - 1] + ordenados[n ~/ 2]) / 2.0;
}
