import 'analisis.dart';
import 'espectro.dart';
import 'ventana.dart';

/// Cuánto aprendió el sistema de una cubeta de velocidad, y cuánto le falta.
///
/// **Existe porque «no hay avisos» quería decir dos cosas opuestas.** Con la
/// pantalla de vibración en silencio no había forma de distinguir «la camioneta
/// está bien» de «todavía no anduve lo suficiente a esa velocidad como para
/// que el sistema sepa qué es normal ahí». Son estados contrarios y se veían
/// idénticos — el mismo error que ya costó tres días con el GPS, que un
/// contador sin la razón al lado no dice nada.
class CoberturaDeCubeta {
  final int cubeta;

  /// Cuántas ventanas de cinco segundos hay guardadas de esta velocidad.
  final int ventanas;

  /// Cuántas hacen falta para que la mediana signifique algo.
  final int necesarias;

  const CoberturaDeCubeta({
    required this.cubeta,
    required this.ventanas,
    this.necesarias = ventanasParaLineaBase,
  });

  bool get lista => ventanas >= necesarias;

  int get faltan => lista ? 0 : necesarias - ventanas;

  /// De 0 a 1. Para una barra, no para decidir nada.
  double get avance =>
      necesarias <= 0 ? 1 : (ventanas / necesarias).clamp(0.0, 1.0);

  /// Cuántos segundos hay que andar a esta velocidad para completarla.
  ///
  /// Es el número que sirve de verdad: «faltan 12 ventanas» no le dice nada a
  /// nadie, «falta un minuto a esa velocidad» sí.
  int get segundosQueFaltan => faltan * segundosPorVentana;

  String get comoVa {
    if (lista) return 'Lista: $ventanas ventanas, ya sabe qué es normal acá.';
    if (ventanas == 0) {
      return 'Sin datos. Hacen falta '
          '${_enMinutos(necesarias * segundosPorVentana)} andando a esta '
          'velocidad.';
    }
    return '$ventanas de $necesarias ventanas · falta '
        '${_enMinutos(segundosQueFaltan)} a esta velocidad.';
  }
}

/// Cuánto dura una ventana, en segundos. Es el mismo número que usa
/// `ServicioVibracion.duracionDeVentana`; acá está para poder traducir
/// «ventanas que faltan» a «tiempo que falta», que es lo único accionable.
const int segundosPorVentana = 5;

String _enMinutos(int segundos) {
  if (segundos < 60) return '$segundos s';
  final m = segundos ~/ 60;
  final s = segundos % 60;
  return s == 0 ? '$m min' : '$m min $s s';
}

/// La cobertura de TODAS las cubetas, incluidas las que no tienen nada.
///
/// **Las vacías entran a propósito.** Una cubeta que falta es justamente lo
/// que hay que ver: dice a qué velocidad hay que salir a andar. Si sólo se
/// listaran las que tienen datos, la pantalla se vería completa estando vacía.
List<CoberturaDeCubeta> cobertura(Map<int, int> ventanasPorCubeta) => [
  for (var c = 0; c <= cubetaMaxima; c++)
    CoberturaDeCubeta(cubeta: c, ventanas: ventanasPorCubeta[c] ?? 0),
];

/// Cuántas vueltas por segundo da la rueda en el centro de una cubeta, y por
/// lo tanto en qué banda hay que mirar un defecto de rueda.
///
/// **El diámetro lo midió Mauro: 76 cm bajo carga**, 2026-09-19. La cubierta
/// es una 265/70R17, que sin carga da 80,3 cm — el 5,3 % de diferencia es el
/// achatamiento por el peso de la camioneta, y es el número que hay que usar
/// acá porque lo que rueda es la rueda cargada.
///
/// **Esto NO toca la odometría, y no puede.** El factor de neumáticos se
/// aprende de la mediana de los cocientes GPS/tablero, nunca se calcula de la
/// medida de la cubierta: es la regla de fondo del proyecto y el motivo es
/// exactamente esta diferencia entre el radio libre y el cargado. Acá el
/// diámetro sirve sólo para interpretar un espectro — decir «un desbalanceo a
/// esta velocidad tendría que aparecer en esta banda»—, que es una ayuda para
/// leer, no una medición.
const double diametroDeRuedaM = 0.76;

double vueltasPorSegundo(double kmh) {
  final circunferencia = 3.141592653589793 * diametroDeRuedaM;
  return (kmh / 3.6) / circunferencia;
}

/// La banda donde caería un defecto de rueda a esa velocidad, o `null` si cae
/// fuera del rango que se mide.
int? bandaDeLaRueda(double kmh) {
  final f = vueltasPorSegundo(kmh);
  for (var b = 0; b < cantidadDeBandas; b++) {
    if (f >= bordesHz[b] && f < bordesHz[b + 1]) return b;
  }
  return null;
}

/// La velocidad del medio de una cubeta, que es con la que se estima la banda.
double velocidadTipicaDe(int cubeta) =>
    velocidadMinimaKmh + cubeta * anchoDeCubeta + anchoDeCubeta / 2;
