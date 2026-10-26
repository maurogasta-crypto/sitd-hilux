/// El tacómetro de la pantalla: la marcha que se OYE, y las RPM que da el GPS
/// con esa marcha, segundo a segundo (`sitd-39`).
///
/// Lo pidió Mauro el 2026-10-17, después del viaje 23 (11 minutos de ciudad):
/// «no era verdaderamente dinámica la visualización de revoluciones, aparecía
/// como dato estático con mucha latencia». Tenía razón, y eran cuatro cosas:
///
///  1. Se escuchaba **un segundo de cada cinco**.
///  2. Sólo arriba de 30 km/h y estable: **28 escuchas en 11 minutos**, con
///     huecos de casi dos minutos.
///  3. Cada escucha decidía SOLA, con 3 dB de ventaja sobre la segunda
///     marcha: **4 de 28 dieron RPM**. En ciudad la 2.ª y la 3.ª se pisan
///     —el 2.º armónico de la 2.ª cae a un 4 % del 3.º de la 3.ª—, y una
///     ventana de un segundo no alcanza para separarlas.
///  4. La pantalla mostraba cada lectura 15 segundos y volvía al texto.
///
/// **Lo que cambia: la marcha se decide con las últimas escuchas JUNTAS**, y
/// mientras esté tomada, las RPM salen de la velocidad del GPS cada segundo:
/// `kmh × rpmPorKmh(marcha)`. Con el viaje 23 juntando tres escuchas salen 12
/// de 28 con marcha, las 12 en 3.ª, y ninguna se contradice; y desde esta
/// tanda se escucha cada segundo, así que caben cinco veces más.
///
/// **Por qué es honesto mostrar RPM «por GPS»**: con la marcha puesta, el
/// motor y las ruedas están unidos por engranajes, y el GPS mide la velocidad
/// mejor que cualquier cosa en el teléfono. Lo único que el GPS no sabe es la
/// marcha, y eso es justo lo que se oye. Cuando la marcha deja de ser
/// creíble —parado, un cambio grande de velocidad, RPM imposibles, mucho rato
/// sin oírla— se suelta y la pantalla lo dice, en vez de inventar.
library;

import 'dart:math' as math;

import 'regimen.dart';

/// Cuántas escuchas recientes se juntan para decidir la marcha.
const int escuchasJuntas = 3;

/// Una escucha más vieja que esto no cuenta para decidir: la marcha pudo
/// haber cambiado.
const int msEscuchaVigente = 12000;

/// Con las escuchas juntas, cuánto tiene que sonar la marcha (media, en dB
/// sobre la mediana) y cuánta ventaja sacarle a la segunda. Más bajos que los
/// de una escucha sola (6 y 3, `regimen.dart`) porque la media de tres
/// ventanas de ruido es más pareja que una sola: el ruido no repite marcha y
/// el motor sí.
///
/// **Medido con el viaje 23**: con 5 y 1,5 dB y tres escuchas, 12 de 28
/// ventanas con marcha, todas 3.ª, sin un solo salto; con 4,5 dB, lo mismo.
const double minimaJuntasDb = 5;
const double margenJuntasDb = 1.5;

/// Abajo de esto no se escucha para la marcha: con el embrague apretado
/// rodando despacio el motor está a ralentí, y el ralentí cae cerca de la 1.ª.
const double kmhMinimaParaOir = 10;

/// Cuándo se suelta una marcha tomada.
const int msMarchaVigente = 90000;
const double kmhMinimaTomada = 5;
const double saltoDeKmh = 15;
const double rpmMaximaTomada = 3800;

/// Lo que muestra la pantalla.
class LecturaTacometro {
  final double rpm;
  final int marcha;

  /// Hace cuánto se OYÓ la marcha por última vez. Las RPM son de ahora (las
  /// da el GPS); la marcha es de hace esto.
  final int oidaHaceMs;

  const LecturaTacometro({
    required this.rpm,
    required this.marcha,
    required this.oidaHaceMs,
  });
}

class _Escucha {
  final int t;
  final List<double?> porMarcha;
  _Escucha(this.t, this.porMarcha);
}

class Tacometro {
  final List<_Escucha> _escuchas = [];

  int? _marcha;
  int? _oidaT;
  double? _kmhAlOirla;

  /// La marcha tomada, o `null`.
  int? get marcha => _marcha;

  void olvidar() {
    _escuchas.clear();
    _marcha = null;
    _oidaT = null;
    _kmhAlOirla = null;
  }

  /// Una escucha nueva: lo que sonó cada marcha ([porMarcha], en dB, de
  /// `LecturaMotor`), con la velocidad de ese segundo. Devuelve la marcha
  /// que quedó tomada (puede ser la de antes).
  int? escuchar(int t, double? kmh, List<double?> porMarcha) {
    if (kmh == null || kmh < kmhMinimaParaOir || porMarcha.isEmpty) {
      return _marcha;
    }
    _escuchas.add(_Escucha(t, porMarcha));
    _escuchas.removeWhere((e) => t - e.t > msEscuchaVigente);
    while (_escuchas.length > escuchasJuntas) {
      _escuchas.removeAt(0);
    }
    final g = decidirMarcha([for (final e in _escuchas) e.porMarcha], kmh: kmh);
    if (g != null) {
      _marcha = g;
      _oidaT = t;
      _kmhAlOirla = kmh;
    }
    // Una escucha que no decide no suelta la marcha: «no sé» no es «otra».
    return _marcha;
  }

  /// Lo que se muestra ahora, con la velocidad de ahora. `null` si no hay
  /// marcha creíble; y si deja de serlo, la suelta.
  LecturaTacometro? leer(int t, double? kmh) {
    final g = _marcha, oida = _oidaT, kmhOida = _kmhAlOirla;
    if (g == null || oida == null || kmhOida == null) return null;
    final rpm = (kmh ?? 0) * rpmPorKmh(g);
    final soltar =
        kmh == null ||
        kmh < kmhMinimaTomada ||
        t - oida > msMarchaVigente ||
        (kmh - kmhOida).abs() > saltoDeKmh ||
        rpm < rpmMinimaEnMarcha ||
        rpm > rpmMaximaTomada;
    if (soltar) {
      _marcha = null;
      return null;
    }
    return LecturaTacometro(rpm: rpm, marcha: g, oidaHaceMs: t - oida);
  }
}

/// La marcha que suena en un grupo de escuchas: la de mayor MEDIA entre las
/// escuchas que la probaron (al menos dos, si hay dos), con la vara y la
/// ventaja de arriba. Las dos marchas a una octava (2.ª y 4.ª) no compiten:
/// son el mismo motor oído una octava abajo, y entre ellas, si empatan, gana
/// la de arriba, como en `leerMotor`.
int? decidirMarcha(List<List<double?>> escuchas, {double? kmh}) {
  if (escuchas.isEmpty) return null;
  final n = relacionesCaja.length;
  final requeridas = escuchas.length >= 2 ? 2 : 1;
  final media = List<double?>.filled(n, null);
  for (var g = 0; g < n; g++) {
    var suma = 0.0;
    var cuantas = 0;
    for (final e in escuchas) {
      final d = g < e.length ? e[g] : null;
      if (d != null) {
        suma += d;
        cuantas++;
      }
    }
    if (cuantas >= requeridas) media[g] = suma / cuantas;
  }
  var mejor = -1;
  for (var g = 0; g < n; g++) {
    final m = media[g];
    if (m != null && (mejor < 0 || m > media[mejor]!)) mejor = g;
  }
  if (mejor < 0) return null;
  // La compañera de octava, empatada, gana si es la de arriba.
  for (var g = 0; g < n; g++) {
    final m = media[g];
    if (m == null || g == mejor || !_aUnaOctava(g, mejor)) continue;
    if (relacionesCaja[g] > relacionesCaja[mejor] &&
        media[mejor]! - m <= margenDeOctavaDb &&
        arribaCreible(g + 1, kmh)) {
      mejor = g;
      break;
    }
  }
  // Y al revés (sitd-49): la de arriba, si no es creíble, cede a la de abajo.
  final elegida = corregirOctavaIncreible(mejor + 1, media, kmh) - 1;
  final puntaje = media[mejor]!;
  mejor = elegida;
  var segunda = double.negativeInfinity;
  for (var g = 0; g < n; g++) {
    final m = media[g];
    if (m == null || g == mejor || _aUnaOctava(g, mejor)) continue;
    if (m > segunda) segunda = m;
  }
  // La evidencia es la misma serie de armónicos: vale el puntaje de la que
  // sonó más, aunque la elegida sea su compañera.
  final m = math.max(media[mejor]!, puntaje);
  if (m < minimaJuntasDb || m - segunda < margenJuntasDb) return null;
  return mejor + 1;
}

bool _aUnaOctava(int g, int h) {
  final r = relacionesCaja[g] / relacionesCaja[h];
  return (r > 1.9 && r < 2.2) || (r > 1 / 2.2 && r < 1 / 1.9);
}
