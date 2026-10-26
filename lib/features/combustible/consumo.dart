import 'carga.dart';

/// El tramo entre dos tanques llenos, que es la única unidad en la que se
/// puede hablar de consumo sin inventar nada.
class Ventana {
  /// Cuándo se llenó el tanque al empezar y al cerrar.
  final int desde;
  final int hasta;

  /// Kilómetros según el odómetro del tablero.
  final double kmTablero;

  /// Los mismos kilómetros, corregidos por el factor de neumáticos. Si el
  /// factor todavía no se aprendió, vale `1` y los dos números coinciden.
  final double kmReales;

  /// Litros que entraron en el tramo: los de la carga que lo cierra más los de
  /// las cargas parciales del medio. **No** incluye los de la carga que lo
  /// abre, que se quemaron en el tramo anterior.
  final double litros;

  /// Lo que costó, por moneda. Un mapa y no un número, porque UYU y USD no se
  /// suman nunca — ni siquiera para mostrar un total.
  final Map<String, double> costo;

  const Ventana({
    required this.desde,
    required this.hasta,
    required this.kmTablero,
    required this.kmReales,
    required this.litros,
    required this.costo,
  });

  /// Litros cada 100 km, que es como se habla de consumo en Uruguay.
  double get litrosCada100 => litros / kmReales * 100;

  double get kmPorLitro => kmReales / litros;

  /// Costo por kilómetro en esa moneda, o `null` si no se anotó el precio.
  double? costoPorKm(String moneda) {
    final c = costo[moneda];
    return c == null || kmReales <= 0 ? null : c / kmReales;
  }
}

/// Todo lo que se puede decir del combustible mirando las cargas juntas.
///
/// **Nada de esto se guarda.** Se calcula al leer, cada vez, desde lo que
/// Mauro tecleó en la estación. Un derivado guardado es un derivado que un día
/// contradice a sus propios datos.
class Consumo {
  final List<Ventana> ventanas;

  /// Litros y kilómetros de todas las ventanas juntas.
  final double litrosTotales;
  final double kmTotales;

  const Consumo({
    required this.ventanas,
    required this.litrosTotales,
    required this.kmTotales,
  });

  bool get hayDatos => ventanas.isNotEmpty && kmTotales > 0;

  /// La ventana más reciente: cómo viene consumiendo ahora.
  Ventana? get ultima => ventanas.isEmpty ? null : ventanas.last;

  /// El promedio de toda la historia.
  ///
  /// **Es litros totales sobre kilómetros totales, no el promedio de los
  /// promedios.** Parece lo mismo y no lo es: un tramo de 40 km pesaría igual
  /// que uno de 600, y alcanzaría una carga corta en ciudad para ensuciar el
  /// número de todo un año.
  double? get litrosCada100 =>
      hayDatos ? litrosTotales / kmTotales * 100 : null;

  /// Cuántos kilómetros rendiría un tanque lleno al consumo promedio.
  ///
  /// **No es cuánto queda en el tanque**: la aplicación no tiene forma de
  /// saberlo — el flotante del tablero no se le puede preguntar sin OBD2, y
  /// esta camioneta no habla OBD2. Es la autonomía de un tanque entero, que es
  /// lo que sirve para decidir si un tramo se hace de una tirada.
  double? autonomia(double litrosDelTanque) {
    final c = litrosCada100;
    return c == null || c <= 0 ? null : litrosDelTanque / c * 100;
  }

  /// Costo por kilómetro de toda la historia, en esa moneda.
  double? costoPorKm(String moneda) {
    if (!hayDatos) return null;
    var total = 0.0;
    var km = 0.0;
    for (final v in ventanas) {
      final c = v.costo[moneda];
      if (c == null) continue;
      total += c;
      km += v.kmReales;
    }
    return km <= 0 ? null : total / km;
  }
}

/// Lo que va desde el último tanque lleno (`sitd-51`, Mauro: «un control
/// para tener la actualización en tiempo real del consumo»). El consumo de
/// verdad recién se sabe en el próximo lleno; mientras tanto se muestra lo
/// que hay: desde cuándo, desde qué odómetro, y cuántas cargas PARCIALES
/// entraron en el medio, con sus litros.
class TramoEnCurso {
  /// La carga que lo abrió: el último tanque lleno.
  final Carga apertura;

  /// Las cargas parciales que vinieron después, de la más vieja a la nueva.
  final List<Carga> parciales;

  const TramoEnCurso({required this.apertura, required this.parciales});

  double get litrosParciales => parciales.fold(0.0, (s, c) => s + c.litros);

  /// El último odómetro anotado en el tramo (el de la apertura o el de la
  /// última parcial).
  double get ultimoOdometro => parciales.isEmpty
      ? apertura.odoTablero
      : parciales.map((c) => c.odoTablero).reduce((a, b) => a > b ? a : b);
}

/// Una lectura del odómetro del tablero: en una carga, o al empezar o
/// terminar un viaje.
typedef LecturaTablero = ({int t, double odo});

/// Los kilómetros del tramo en curso (`sitd-52`, Mauro: «el cálculo de
/// kilómetros tiene que ser en base al tacómetro del auto, corregido por la
/// corrección que hace el sistema en base al GPS»). Es la misma cuenta que el
/// consumo: el TABLERO por el factor [k]. Del tablero se usa la lectura más
/// nueva que se anotó después del lleno (una parcial, o el odómetro de un
/// viaje); el GPS sólo pone lo que falta desde esa lectura hasta ahora
/// ([kmGpsDesde]), porque el tablero no se puede leer solo.
({double kmTablero, double kmCorregidos, double kmGps, LecturaTablero ultima})
kmDelTramo(
  TramoEnCurso tramo, {
  required List<LecturaTablero> otras,
  required double k,
  required double Function(int t) kmGpsDesde,
}) {
  LecturaTablero ultima = (t: tramo.apertura.t, odo: tramo.apertura.odoTablero);
  for (final l in [
    for (final c in tramo.parciales) (t: c.t, odo: c.odoTablero),
    ...otras,
  ]) {
    // Sólo lo posterior al lleno y que no retrocede: un odómetro mal
    // tecleado no puede restar kilómetros.
    if (l.t < tramo.apertura.t || l.odo < ultima.odo) continue;
    if (l.t >= ultima.t) ultima = l;
  }
  final kmTablero = ultima.odo - tramo.apertura.odoTablero;
  final kmGps = kmGpsDesde(ultima.t);
  return (
    kmTablero: kmTablero,
    kmCorregidos: kmTablero * k,
    kmGps: kmGps,
    ultima: ultima,
  );
}

/// El tramo abierto, o `null` si todavía no hubo un tanque lleno.
TramoEnCurso? tramoEnCurso(List<Carga> cargas) {
  final orden = [...cargas]..sort((a, b) => a.t.compareTo(b.t));
  var i = orden.lastIndexWhere((c) => c.tanqueLleno);
  if (i < 0) return null;
  return TramoEnCurso(apertura: orden[i], parciales: orden.sublist(i + 1));
}

/// Calcula el consumo de lleno a lleno.
///
/// **Por qué de lleno a lleno y no carga a carga.** La única vez que se sabe
/// cuánto combustible hay adentro del tanque es cuando rebalsa. Entre dos
/// tanques llenos, los litros que entraron son exactamente los que se
/// quemaron, y los kilómetros los da el odómetro. Cualquier otra cuenta
/// depende de adivinar cuánto quedaba, y ese error no se compensa: se arrastra
/// a todas las cargas siguientes.
///
/// Las cargas parciales no se tiran: sus litros entran en la ventana que las
/// contiene. Lo que no hacen es cerrarla.
///
/// [k] es el factor de neumáticos. Traduce el odómetro del tablero a
/// kilómetros reales y **nunca se le aplica a la odometría GPS**, que ya mide
/// la distancia de verdad.
Consumo calcularConsumo(List<Carga> cargas, {double k = 1.0}) {
  final orden = [...cargas]..sort((a, b) => a.t.compareTo(b.t));
  final ventanas = <Ventana>[];

  Carga? apertura;
  var litros = 0.0;
  var costo = <String, double>{};

  for (final c in orden) {
    if (apertura == null) {
      // Hasta el primer tanque lleno no hay nada que medir: no se sabe con
      // cuánto se venía andando.
      if (c.tanqueLleno) apertura = c;
      continue;
    }

    litros += c.litros;
    final importe = c.costo;
    if (importe != null) {
      costo[c.moneda] = (costo[c.moneda] ?? 0) + importe;
    }

    if (!c.tanqueLleno) continue;

    final kmTablero = c.odoTablero - apertura.odoTablero;
    if (kmTablero > 0 && litros > 0) {
      ventanas.add(
        Ventana(
          desde: apertura.t,
          hasta: c.t,
          kmTablero: kmTablero,
          kmReales: kmTablero * k,
          litros: litros,
          costo: Map.unmodifiable(costo),
        ),
      );
    }
    // Si el odómetro no avanzó, el tramo se descarta y no se arrastra: casi
    // siempre es un número mal tecleado, y meterlo ensuciaría el promedio para
    // siempre.
    apertura = c;
    litros = 0;
    costo = <String, double>{};
  }

  var litrosTotales = 0.0;
  var kmTotales = 0.0;
  for (final v in ventanas) {
    litrosTotales += v.litros;
    kmTotales += v.kmReales;
  }

  return Consumo(
    ventanas: ventanas,
    litrosTotales: litrosTotales,
    kmTotales: kmTotales,
  );
}
