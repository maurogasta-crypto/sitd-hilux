import 'dart:math' as math;

import 'espectro.dart';
import 'ventana.dart';

/// Cuántas ventanas hace falta tener de una cubeta para que su línea base
/// signifique algo.
///
/// Treinta ventanas son unos dos minutos y medio de andar a esa velocidad. Con
/// menos, la mediana se mueve con cada viaje nuevo y cualquier cosa parece una
/// anomalía — que es la forma más rápida de que alguien deje de mirar los
/// avisos.
const int ventanasParaLineaBase = 30;

/// Cuántos desvíos típicos tiene que apartarse una banda para sospechar.
const double umbralDeDesvio = 6;

/// Cuántos viajes seguidos tiene que repetirse antes de decir una palabra.
///
/// **Nunca se alerta por una muestra**, ni por un viaje: un camino de tierra,
/// una carga pesada o una rueda con barro pegado alcanzan para mover una banda
/// en un viaje entero. Lo que no hacen es repetirse idéntico tres veces.
const int viajesSeguidosParaAvisar = 3;

/// Lo normal de una cubeta de velocidad, aprendido de la historia.
class LineaBase {
  final int cubeta;
  final int ventanas;

  /// Mediana por banda. **Mediana y no promedio**, por lo mismo que el factor
  /// de neumáticos: un solo pozo grande le movería el promedio a toda la
  /// cubeta, y un pozo es exactamente lo que va a pasar.
  final List<double> mediana;

  /// Desviación absoluta mediana, por banda: cuánto se mueve normalmente.
  final List<double> mad;

  const LineaBase({
    required this.cubeta,
    required this.ventanas,
    required this.mediana,
    required this.mad,
  });

  bool get suficiente => ventanas >= ventanasParaLineaBase;
}

/// Una banda que se salió de lo normal, en un viaje y en una cubeta.
class Desvio {
  final int cubeta;
  final int banda;

  /// Cuántas desviaciones típicas por encima de lo normal. **Sólo hacia
  /// arriba**: que una banda vibre MENOS que antes no es una falla mecánica
  /// que avisar — es un camino mejor, una carga distinta, o una rueda que se
  /// limpió sola.
  final double z;

  /// Cuánto vale ahora y cuánto valía, para poder mostrarlo sin hablar de
  /// desviaciones típicas con alguien que está por subirse a manejar.
  final double ahora;
  final double normal;

  final int ventanas;

  const Desvio({
    required this.cubeta,
    required this.banda,
    required this.z,
    required this.ahora,
    required this.normal,
    required this.ventanas,
  });

  /// La frecuencia donde está el problema, en palabras.
  String get rango =>
      '${bordesHz[banda].toStringAsFixed(1).replaceAll('.', ',')} a '
      '${bordesHz[banda + 1].toStringAsFixed(1).replaceAll('.', ',')} Hz';
}

/// Algo que se repitió lo suficiente como para decirlo.
class Anomalia {
  final int cubeta;
  final int banda;

  /// El desvío más chico de los viajes en que apareció: es el que hay que
  /// mostrar, no el más grande. El número que se dice tiene que ser el que se
  /// sostiene siempre, no el peor día.
  final double z;

  final int viajes;
  final Desvio ultimo;

  const Anomalia({
    required this.cubeta,
    required this.banda,
    required this.z,
    required this.viajes,
    required this.ultimo,
  });
}

/// Calcula la línea base por cubeta.
///
/// [excepto] deja afuera viajes: se usa para no meter en la línea base los
/// mismos viajes que se están evaluando. Sin eso, una falla que empieza y se
/// queda se iría metiendo de a poco en «lo normal» hasta dejar de verse — que
/// es justo lo que no se quiere de un detector de anomalías.
Map<int, LineaBase> lineaBase(
  Map<int, List<VentanaVibracion>> porViaje, {
  Set<int> excepto = const {},
}) {
  final porCubeta = <int, List<VentanaVibracion>>{};
  porViaje.forEach((viaje, ventanas) {
    if (excepto.contains(viaje)) return;
    for (final v in ventanas) {
      if (!v.completa) continue;
      (porCubeta[v.cubeta] ??= []).add(v);
    }
  });

  final base = <int, LineaBase>{};
  porCubeta.forEach((cubeta, ventanas) {
    final mediana = List<double>.filled(cantidadDeBandas, 0);
    final mad = List<double>.filled(cantidadDeBandas, 0);
    for (var b = 0; b < cantidadDeBandas; b++) {
      final valores = [for (final v in ventanas) v.bandas[b]]..sort();
      final m = _mediana(valores);
      mediana[b] = m;
      final desvios = [for (final x in valores) (x - m).abs()]..sort();
      mad[b] = _mediana(desvios);
    }
    base[cubeta] = LineaBase(
      cubeta: cubeta,
      ventanas: ventanas.length,
      mediana: mediana,
      mad: mad,
    );
  });
  return base;
}

/// Compara un viaje contra la línea base y devuelve lo que se salió.
List<Desvio> compararViaje(
  List<VentanaVibracion> delViaje,
  Map<int, LineaBase> base, {
  double umbral = umbralDeDesvio,
  int minimoDeVentanas = 5,
}) {
  final porCubeta = <int, List<VentanaVibracion>>{};
  for (final v in delViaje) {
    if (v.completa) (porCubeta[v.cubeta] ??= []).add(v);
  }

  final desvios = <Desvio>[];
  porCubeta.forEach((cubeta, ventanas) {
    // Un solo tramo corto a esa velocidad no alcanza para decir nada: puede
    // ser el pedazo de camino malo que hay antes del puente.
    if (ventanas.length < minimoDeVentanas) return;
    final b = base[cubeta];
    if (b == null || !b.suficiente) return;

    for (var banda = 0; banda < cantidadDeBandas; banda++) {
      final valores = [for (final v in ventanas) v.bandas[banda]]..sort();
      final ahora = _mediana(valores);
      final z = _zRobusto(ahora, b.mediana[banda], b.mad[banda]);
      if (z >= umbral) {
        desvios.add(
          Desvio(
            cubeta: cubeta,
            banda: banda,
            z: z,
            ahora: ahora,
            normal: b.mediana[banda],
            ventanas: ventanas.length,
          ),
        );
      }
    }
  });
  desvios.sort((a, b) => b.z.compareTo(a.z));
  return desvios;
}

/// Las anomalías que aguantan la histéresis.
///
/// [ultimosViajes] son los identificadores de los viajes más nuevos, del más
/// nuevo al más viejo. Una anomalía existe sólo si la MISMA banda de la MISMA
/// cubeta se pasó del umbral en los [seguidos] viajes de esa lista que tengan
/// datos de esa cubeta — no en tres viajes cualesquiera.
List<Anomalia> anomalias(
  Map<int, List<VentanaVibracion>> porViaje,
  List<int> ultimosViajes, {
  double umbral = umbralDeDesvio,
  int seguidos = viajesSeguidosParaAvisar,
}) {
  final candidatos = ultimosViajes.take(seguidos).toList();
  if (candidatos.length < seguidos) return const [];

  final base = lineaBase(porViaje, excepto: candidatos.toSet());

  // Se evalúa viaje por viaje contra la MISMA línea base, que deja afuera a
  // los tres. Si cada viaje se comparara contra una base distinta, tres
  // resultados no serían comparables entre sí y la histéresis no probaría
  // nada.
  final porViajeDesvios = <int, Map<String, Desvio>>{};
  for (final viaje in candidatos) {
    final desvios = compararViaje(
      porViaje[viaje] ?? const [],
      base,
      umbral: umbral,
    );
    porViajeDesvios[viaje] = {
      for (final d in desvios) '${d.cubeta}:${d.banda}': d,
    };
  }

  final primero = porViajeDesvios[candidatos.first] ?? const {};
  final salida = <Anomalia>[];
  for (final clave in primero.keys) {
    final encontrados = [
      for (final viaje in candidatos)
        if (porViajeDesvios[viaje]?[clave] != null)
          porViajeDesvios[viaje]![clave]!,
    ];
    if (encontrados.length < seguidos) continue;
    final d = primero[clave]!;
    salida.add(
      Anomalia(
        cubeta: d.cubeta,
        banda: d.banda,
        z: encontrados.map((x) => x.z).reduce(math.min),
        viajes: encontrados.length,
        ultimo: d,
      ),
    );
  }
  salida.sort((a, b) => b.z.compareTo(a.z));
  return salida;
}

/// Desvío robusto: cuántas «desviaciones típicas» por encima de lo normal.
///
/// El 1,4826 es lo que convierte una desviación absoluta mediana en algo
/// comparable con la desviación estándar de siempre, para una distribución
/// normal. Se usa la mediana en vez del promedio por lo mismo de siempre: un
/// pozo no tiene que mover la referencia.
double _zRobusto(double valor, double mediana, double mad) {
  // Un MAD en cero pasa de verdad —pocas ventanas, todas casi iguales— y
  // dividir por él daría infinito, o sea «anomalía» en cuanto cambie el
  // último decimal. Se usa un piso relativo a la propia mediana.
  final escala = math.max(1.4826 * mad, math.max(mediana * 0.05, 1e-6));
  final z = (valor - mediana) / escala;
  return z.isFinite ? z : 0;
}

double _mediana(List<double> ordenados) {
  if (ordenados.isEmpty) return 0;
  final n = ordenados.length;
  if (n.isOdd) return ordenados[n ~/ 2];
  return (ordenados[n ~/ 2 - 1] + ordenados[n ~/ 2]) / 2;
}
