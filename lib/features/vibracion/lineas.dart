import 'dart:math' as math;

import '../audio/regimen.dart';
import 'analisis.dart';
import 'rueda.dart';
import 'ventana.dart';

/// Las LÍNEAS: frecuencias que se repiten porque las produce algo que gira
/// (`sitd-55`, `hilux:D7`).
///
/// Mauro, 26-oct: «la idea es que la APK pueda comenzar a detectar pequeñas
/// variaciones en las frecuencias que se repiten para observarlas como
/// falla». Los viajes 23 y 24 del Note 9 (137 y 240 km, a 201 Hz) dieron las
/// MISMAS líneas, y cada una con dueño (`MEDICION.md`, «Las líneas que se
/// repiten»): la rueda 2× (la más saliente), la rueda 3×, el cardán y el
/// encendido.
///
/// **Por qué por línea y no por banda.** Las ocho bandas de `analisis.dart`
/// miran cómo se reparte la vibración entre 0,5 y 25 Hz: ven un cambio
/// grande en una zona. Una línea es un casillero de 0,2 Hz que se sabe dónde
/// cae, porque la velocidad del GPS y la marcha dicen a qué frecuencia gira
/// cada pieza: se puede seguir aunque sea chica, y se ve si se CORRE.
///
/// Cada línea da dos números por ventana:
/// · **veces**: cuántas veces sobre la mediana de su entorno (±3 Hz) está el
///   pico. Si crece, esa pieza vibra más que antes.
/// · **corrimiento**: cuánto se apartó el pico de donde tenía que estar, en
///   %. Una rueda 2× que aparece un 2 % más abajo es una rueda que gira más
///   despacio de lo que dice el GPS: más chica —menos presión, otra
///   cubierta— o patinando.
///
/// Las del motor (`m1`, `m2`) necesitan la marcha OÍDA (`tacometro.dart`);
/// sin marcha tomada no se miden. Las de la rueda y el cardán, sólo la
/// velocidad.
enum Linea {
  r1('r1', 'Rueda, 1 vez por vuelta'),
  r2('r2', 'Rueda, 2 veces por vuelta'),
  r3('r3', 'Rueda, 3 veces por vuelta'),
  c1('c1', 'Cardán, 1 vez por vuelta'),
  m1('m1', 'Motor, 1 vez por vuelta'),
  m2('m2', 'Encendido del motor');

  final String clave;
  final String nombre;
  const Linea(this.clave, this.nombre);

  static Linea? deClave(String c) {
    for (final l in values) {
      if (l.clave == c) return l;
    }
    return null;
  }

  /// Si depende de la marcha.
  bool get delMotor => this == m1 || this == m2;

  /// A qué frecuencia tiene que estar, en Hz, o `null` si no se sabe.
  double? frecuencia(double kmh, int? marcha) {
    final rueda = frecuenciaDeRueda(kmh);
    final cardan = rueda * relacionDiferencial;
    switch (this) {
      case r1:
        return rueda;
      case r2:
        return 2 * rueda;
      case r3:
        return 3 * rueda;
      case c1:
        return cardan;
      case m1:
      case m2:
        if (marcha == null || marcha < 1 || marcha > relacionesCaja.length) {
          return null;
        }
        final motor = cardan * relacionesCaja[marcha - 1];
        return this == m1 ? motor : 2 * motor;
    }
  }
}

/// Lo que dio una línea en una ventana.
class MedidaDeLinea {
  /// Veces sobre la mediana de su entorno.
  final double veces;

  /// Cuánto se corrió el pico de donde tenía que estar, en %.
  final double corrimiento;

  const MedidaDeLinea(this.veces, this.corrimiento);
}

/// Cuánto se busca alrededor de la frecuencia esperada: la velocidad cambia
/// dentro de los 5 s de la ventana, y la marcha es la de las RPM por km/h.
const double holguraDeLinea = 0.03;

/// El entorno contra el que se mide cuánto sobresale una línea, en Hz.
const double entornoDeLineaHz = 3;

/// Mide las líneas en el espectro de una ventana. [espectro] son las
/// magnitudes (como las da `magnitudes`), [hz] la frecuencia de muestreo,
/// [kmh] la velocidad media de la ventana y [marcha] la tomada, si hay.
Map<Linea, MedidaDeLinea> medirLineas(
  List<double> espectro,
  double hz, {
  required double? kmh,
  int? marcha,
}) {
  if (kmh == null || !kmh.isFinite || kmh < velocidadMinimaKmh) {
    return const {};
  }
  if (espectro.length < 16 || !hz.isFinite || hz <= 0) return const {};
  final porCasillero = hz / (espectro.length * 2);
  final techo = math.min(100.0, hz / 2 - 1);
  final salida = <Linea, MedidaDeLinea>{};
  for (final l in Linea.values) {
    final f = l.frecuencia(kmh, marcha);
    if (f == null || f < 1 || f > techo - entornoDeLineaHz) continue;
    final centro = f / porCasillero;
    final ancho = math.max(2, (centro * holguraDeLinea).ceil());
    final desde = math.max(1, centro.round() - ancho);
    final hasta = math.min(espectro.length - 2, centro.round() + ancho);
    var k = desde;
    for (var j = desde; j <= hasta; j++) {
      if (espectro[j] > espectro[k]) k = j;
    }
    final e = (entornoDeLineaHz / porCasillero).round();
    final entorno = [
      for (
        var j = math.max(1, k - e);
        j <= math.min(espectro.length - 1, k + e);
        j++
      )
        espectro[j],
    ]..sort();
    final mediana = entorno[entorno.length ~/ 2];
    if (!(mediana > 0)) continue;
    final a = espectro[k - 1], b = espectro[k], c = espectro[k + 1];
    final den = a - 2 * b + c;
    final afinado = k + (den == 0 ? 0.0 : (0.5 * (a - c) / den).clamp(-1, 1));
    salida[l] = MedidaDeLinea(
      double.parse((b / mediana).toStringAsFixed(1)),
      double.parse(((afinado * porCasillero / f - 1) * 100).toStringAsFixed(1)),
    );
  }
  return salida;
}

/// Cómo se guardan en la base: `r2:5.1:-0.4;c1:3.2:0.1`.
String lineasATexto(Map<Linea, MedidaDeLinea> m) => [
  for (final e in m.entries)
    '${e.key.clave}:${e.value.veces}:${e.value.corrimiento}',
].join(';');

Map<Linea, MedidaDeLinea> lineasDeTexto(String? t) {
  if (t == null || t.isEmpty) return const {};
  final salida = <Linea, MedidaDeLinea>{};
  for (final pedazo in t.split(';')) {
    final p = pedazo.split(':');
    if (p.length != 3) continue;
    final l = Linea.deClave(p[0]);
    final v = double.tryParse(p[1]);
    final c = double.tryParse(p[2]);
    if (l == null || v == null || c == null) continue;
    salida[l] = MedidaDeLinea(v, c);
  }
  return salida;
}

/// Para el reporte: `{"r2": [5.1, -0.4], …}`.
Map<String, List<double>> lineasAMapa(Map<Linea, MedidaDeLinea> m) => {
  for (final e in m.entries) e.key.clave: [e.value.veces, e.value.corrimiento],
};

// ─── La comparación ────────────────────────────────────────────────────────

/// Cuánto tiene que crecer una línea, además del desvío, para decirlo: una
/// vez y media lo normal. Con la MAD sola, una línea muy pareja «se saldría»
/// con un cambio que no se nota en nada.
const double crecimientoMinimo = 1.5;

/// Cuánto se tiene que correr, además del desvío, en puntos de %. El GPS y
/// la vuelta medida no son exactos al 1 %, y la velocidad cambia dentro de
/// la ventana: menos que esto es ruido de la cuenta.
const double corrimientoMinimo = 1.0;

/// Qué le pasa a una línea.
enum QueCambio { crece, seCorre }

/// Lo normal de una línea en una cubeta.
class BaseDeLinea {
  final int ventanas;
  final double veces;
  final double madVeces;
  final double corrimiento;
  final double madCorrimiento;

  const BaseDeLinea({
    required this.ventanas,
    required this.veces,
    required this.madVeces,
    required this.corrimiento,
    required this.madCorrimiento,
  });

  bool get suficiente => ventanas >= ventanasParaLineaBase;
}

/// Una línea que se salió en un viaje.
class DesvioDeLinea {
  final Linea linea;
  final int cubeta;
  final QueCambio que;
  final double z;
  final double ahora;
  final double normal;
  final int ventanas;

  const DesvioDeLinea({
    required this.linea,
    required this.cubeta,
    required this.que,
    required this.z,
    required this.ahora,
    required this.normal,
    required this.ventanas,
  });

  String get clave => '${linea.clave}:$cubeta:${que.name}';

  /// En palabras, para la pantalla y la bitácora.
  String get texto {
    final donde = '${linea.nombre}, a ${nombreDeCubeta(cubeta)}';
    return que == QueCambio.crece
        ? '$donde: sobresale ${_d(ahora)} veces (lo normal, ${_d(normal)}).'
        : '$donde: se corrió ${_d(ahora)} % (lo normal, ${_d(normal)} %).';
  }

  Map<String, dynamic> aMapa() => {
    'linea': linea.clave,
    'cubeta': cubeta,
    'que': que.name,
    'z': double.parse(z.toStringAsFixed(1)),
    'ahora': ahora,
    'normal': double.parse(normal.toStringAsFixed(2)),
    'ventanas': ventanas,
  };

  static String _d(double x) => x.toStringAsFixed(1).replaceAll('.', ',');
}

/// Una línea que se salió en los últimos viajes seguidos: ésa se avisa.
class AnomaliaDeLinea {
  final DesvioDeLinea ultimo;
  final int viajes;
  final double z;

  const AnomaliaDeLinea({
    required this.ultimo,
    required this.viajes,
    required this.z,
  });

  Map<String, dynamic> aMapa() => {
    ...ultimo.aMapa(),
    'viajes': viajes,
    'zMinimo': double.parse(z.toStringAsFixed(1)),
  };
}

/// Las ventanas que entran: las mismas que entran a la comparación por
/// bandas (frecuencia suficiente, el teléfono quieto), medidas a 200 Hz.
bool _entra(VentanaVibracion v) =>
    seCompara(v) &&
    !v.movido &&
    claseDeMuestreo(v.hz) == 1 &&
    v.lineas.isNotEmpty;

/// La línea base de cada línea, por cubeta. [excepto]: los viajes que se
/// están evaluando, por lo mismo que en `analisis.dart`.
Map<String, BaseDeLinea> baseDeLineas(
  Map<int, List<VentanaVibracion>> porViaje, {
  Set<int> excepto = const {},
}) {
  final veces = <String, List<double>>{};
  final corr = <String, List<double>>{};
  porViaje.forEach((viaje, ventanas) {
    if (excepto.contains(viaje)) return;
    for (final v in ventanas) {
      if (!_entra(v)) continue;
      v.lineas.forEach((l, m) {
        final k = '${l.clave}:${v.cubeta}';
        (veces[k] ??= []).add(m.veces);
        (corr[k] ??= []).add(m.corrimiento);
      });
    }
  });
  return {
    for (final k in veces.keys)
      k: BaseDeLinea(
        ventanas: veces[k]!.length,
        veces: _mediana(veces[k]!),
        madVeces: _mad(veces[k]!),
        corrimiento: _mediana(corr[k]!),
        madCorrimiento: _mad(corr[k]!),
      ),
  };
}

/// Lo que se salió en UN viaje contra [base]. Para la grabación alcanza con
/// esto (`sitd-55`): grabar es juntar evidencia, avisar es otra cosa.
List<DesvioDeLinea> compararLineas(
  List<VentanaVibracion> delViaje,
  Map<String, BaseDeLinea> base, {
  double umbral = umbralDeDesvio,
  int minimoDeVentanas = 5,
}) {
  final veces = <String, List<double>>{};
  final corr = <String, List<double>>{};
  for (final v in delViaje) {
    if (!_entra(v)) continue;
    v.lineas.forEach((l, m) {
      final k = '${l.clave}:${v.cubeta}';
      (veces[k] ??= []).add(m.veces);
      (corr[k] ??= []).add(m.corrimiento);
    });
  }
  final salida = <DesvioDeLinea>[];
  for (final k in veces.keys) {
    final n = veces[k]!.length;
    final b = base[k];
    if (n < minimoDeVentanas || b == null || !b.suficiente) continue;
    final partes = k.split(':');
    final linea = Linea.deClave(partes[0])!;
    final cubeta = int.parse(partes[1]);

    final ahora = _mediana(veces[k]!);
    final zv =
        (ahora - b.veces) / math.max(1.4826 * b.madVeces, 0.05 * b.veces);
    if (zv >= umbral && ahora >= crecimientoMinimo * b.veces) {
      salida.add(
        DesvioDeLinea(
          linea: linea,
          cubeta: cubeta,
          que: QueCambio.crece,
          z: zv,
          ahora: ahora,
          normal: b.veces,
          ventanas: n,
        ),
      );
    }
    // Se corre sólo si la línea se ve: una que no sobresale no tiene dónde
    // estar, y su «corrimiento» es el de cualquier casillero del ruido.
    if (b.veces < 2) continue;
    final c = _mediana(corr[k]!);
    // El corrimiento de un viaje es la MEDIANA de sus ventanas, y su error
    // es el de una mediana (1,25 × σ / √n), no el de una ventana sola: con
    // la de una ventana, un 2 % —una cubierta con media atmósfera menos—
    // quedaba justo en el borde. Lo que lo frena es [corrimientoMinimo], que
    // es físico: menos de 1 % es ruido de la cuenta.
    final error =
        1.2533 * math.max(1.4826 * b.madCorrimiento, 0.1) / math.sqrt(n);
    final zc = (c - b.corrimiento).abs() / error;
    if (zc >= umbral && (c - b.corrimiento).abs() >= corrimientoMinimo) {
      salida.add(
        DesvioDeLinea(
          linea: linea,
          cubeta: cubeta,
          que: QueCambio.seCorre,
          z: zc,
          ahora: c,
          normal: b.corrimiento,
          ventanas: n,
        ),
      );
    }
  }
  salida.sort((a, b) => b.z.compareTo(a.z));
  return salida;
}

/// Las que se repiten en los [seguidos] viajes más nuevos: la misma regla
/// de siempre, nunca se avisa por un viaje.
List<AnomaliaDeLinea> anomaliasDeLineas(
  Map<int, List<VentanaVibracion>> porViaje,
  List<int> ultimosViajes, {
  int seguidos = viajesSeguidosParaAvisar,
}) {
  final candidatos = ultimosViajes.take(seguidos).toList();
  if (candidatos.length < seguidos) return const [];
  final base = baseDeLineas(porViaje, excepto: candidatos.toSet());
  final porViajeDesvios = {
    for (final viaje in candidatos)
      viaje: {
        for (final d in compararLineas(porViaje[viaje] ?? const [], base))
          d.clave: d,
      },
  };
  final primero = porViajeDesvios[candidatos.first]!;
  final salida = <AnomaliaDeLinea>[];
  for (final clave in primero.keys) {
    final todos = [
      for (final v in candidatos)
        if (porViajeDesvios[v]![clave] != null) porViajeDesvios[v]![clave]!,
    ];
    if (todos.length < seguidos) continue;
    salida.add(
      AnomaliaDeLinea(
        ultimo: primero[clave]!,
        viajes: todos.length,
        z: todos.map((d) => d.z).reduce(math.min),
      ),
    );
  }
  salida.sort((a, b) => b.z.compareTo(a.z));
  return salida;
}

double _mediana(List<double> xs) {
  if (xs.isEmpty) return 0;
  final o = List<double>.from(xs)..sort();
  final n = o.length;
  return n.isOdd ? o[n ~/ 2] : (o[n ~/ 2 - 1] + o[n ~/ 2]) / 2;
}

double _mad(List<double> xs) {
  final m = _mediana(xs);
  return _mediana([for (final x in xs) (x - m).abs()]);
}
