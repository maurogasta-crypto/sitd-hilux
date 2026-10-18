import 'dart:math' as math;

import 'sacudon.dart';
import 'ventana.dart';

/// Cómo está puesto el teléfono y cuánto dobla la camioneta, ventana por
/// ventana (`sitd-42`). Lo pidió Mauro el 2026-10-18, al ver que el Note 9 —el
/// que va en la cabina— tiene giróscopo: «hacé la sitd-42 con el giróscopo».
///
/// Contesta dos preguntas que el espectro solo no podía:
///
///  - **¿Esto es una curva?** El giro medio de la ventana, con el sesgo del
///    giróscopo descontado. El sesgo se mide PARADO —la única vez que se sabe
///    que lo que gira es cero— y hasta la primera parada el giro no se dice:
///    el Note 9 quieto marca 0,038 rad/s, casi lo mismo que una curva de ruta.
///
///  - **¿El teléfono se movió en el soporte?** La gravedad promedio de la
///    ventana, vista desde el teléfono, tiene que apuntar siempre igual. Si se
///    corre más de [anguloDeMovido] grados durante [ventanasParaMovido]
///    ventanas seguidas, el teléfono cambió de posición: se anota, y la
///    posición nueva pasa a ser la de referencia. Las ventanas corridas no se
///    comparan, porque lo que midieron es en parte el teléfono moviéndose.
///    **Sale de la gravedad y no de integrar el giróscopo**: integrando, el
///    sesgo suma para siempre; la gravedad está ahí en cada ventana.
///
/// Sólo se mira la gravedad cuando se la puede leer: con el módulo cerca de
/// 9,81 y sin curva. Una frenada fuerte también corre la gravedad —0,3 g son
/// 17°—, pero no dura tres ventanas.
class Postura {
  final List<double> _sesgo = [0, 0, 0];
  bool _sesgoMedido = false;
  List<double>? _referencia;
  int _fueraSeguidas = 0;

  final List<double> _sumaGiro = [0, 0, 0];
  int _giros = 0;
  final List<double> _sumaA = [0, 0, 0];
  int _aceleraciones = 0;

  bool get sesgoMedido => _sesgoMedido;

  void giro(Giro g) {
    _sumaGiro[0] += g.x;
    _sumaGiro[1] += g.y;
    _sumaGiro[2] += g.z;
    _giros++;
  }

  void aceleracion(Sacudon s) {
    final x = s.x, y = s.y, z = s.z;
    if (x == null || y == null || z == null) return;
    _sumaA[0] += x;
    _sumaA[1] += y;
    _sumaA[2] += z;
    _aceleraciones++;
  }

  /// Un viaje nuevo arranca sin referencia: el teléfono se puede haber puesto
  /// distinto. El sesgo del giróscopo se conserva: es del sensor, no del
  /// viaje.
  void nuevoViaje() {
    _referencia = null;
    _fueraSeguidas = 0;
    _vaciar();
  }

  /// Cierra la ventana con la velocidad de ese momento.
  ({double? giro, double? angulo, bool movido, double? seMovio}) cerrar(
    double? kmh,
  ) {
    double? giro;
    if (_giros > 0) {
      final m = [for (final s in _sumaGiro) s / _giros];
      if (kmh != null && kmh < 1) {
        for (var i = 0; i < 3; i++) {
          _sesgo[i] = _sesgoMedido ? 0.7 * _sesgo[i] + 0.3 * m[i] : m[i];
        }
        _sesgoMedido = true;
      }
      if (_sesgoMedido) {
        giro = _modulo([for (var i = 0; i < 3; i++) m[i] - _sesgo[i]]);
      }
    }

    double? angulo;
    var movido = false;
    double? seMovio;
    if (_aceleraciones > 0) {
      final a = [for (final s in _sumaA) s / _aceleraciones];
      final modulo = _modulo(a);
      final legible =
          (modulo - 9.81).abs() < 0.6 && (giro == null || giro < giroDeCurva);
      final ref = _referencia;
      if (modulo > 0) {
        final u = [for (final v in a) v / modulo];
        if (ref == null) {
          if (legible) {
            _referencia = u;
            angulo = 0;
          }
        } else {
          angulo = _grados(u, ref);
          if (legible) {
            if (angulo > anguloDeMovido) {
              movido = true;
              _fueraSeguidas++;
              if (_fueraSeguidas >= ventanasParaMovido) {
                seMovio = angulo;
                _referencia = u;
                _fueraSeguidas = 0;
              }
            } else {
              _fueraSeguidas = 0;
            }
          }
        }
      }
    }
    _vaciar();
    return (giro: giro, angulo: angulo, movido: movido, seMovio: seMovio);
  }

  void _vaciar() {
    for (var i = 0; i < 3; i++) {
      _sumaGiro[i] = 0;
      _sumaA[i] = 0;
    }
    _giros = 0;
    _aceleraciones = 0;
  }

  static double _modulo(List<double> v) =>
      math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

  static double _grados(List<double> u, List<double> v) {
    final p = (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]).clamp(-1.0, 1.0);
    return math.acos(p) * 180 / math.pi;
  }
}

/// Más de esto contra la referencia es «se corrió». Una pendiente fuerte de
/// ruta son 6°, y una aceleración pareja de 0,15 g otros 8,5: 15° no salen de
/// manejar.
const double anguloDeMovido = 15;

/// Cuántas ventanas seguidas corrido para decir «se movió»: 15 segundos.
const int ventanasParaMovido = 3;
