import 'dart:math' as math;

import 'muestra.dart';

/// Umbrales con los que se acepta o se descarta una muestra del GPS.
///
/// Los valores por defecto son conservadores a propósito: es preferible
/// descartar una muestra buena que integrar una mala, porque el error de
/// distancia no se compensa —siempre suma.
class CriteriosGps {
  /// Error horizontal máximo tolerado, en metros.
  final double precisionMaxima;

  /// Error máximo tolerado de la velocidad, en m/s. Las muestras que no lo
  /// informan se aceptan: Android no siempre lo da y descartarlas dejaría
  /// teléfonos enteros sin odometría.
  final double precisionVelMaxima;

  /// Por debajo de esto se considera que el vehículo está detenido y la
  /// velocidad se toma como cero. Es el filtro que evita acumular metros
  /// parado en un semáforo.
  final double velocidadMinima;

  /// Por encima de esto la muestra es implausible para una camioneta y se
  /// descarta (rebote de señal entre edificios, salto del receptor).
  final double velocidadMaxima;

  /// Si entre dos muestras aceptadas pasó más que esto, no se puentea: el
  /// tramo se corta. Integrar a través de un túnel de tres minutos inventa
  /// una línea recta que el vehículo nunca hizo.
  final int huecoMaximoMs;

  const CriteriosGps({
    this.precisionMaxima = 20.0,
    this.precisionVelMaxima = 2.0,
    this.velocidadMinima = 0.5,
    this.velocidadMaxima = 60.0,
    this.huecoMaximoMs = 5000,
  });
}

/// Lo que devuelve una integración, con el detalle suficiente para saber si
/// hay que desconfiar del número.
class ResultadoOdometria {
  /// Distancia por integración de la velocidad Doppler. **Es la buena.**
  final double metros;

  /// Distancia sumando haversine entre posiciones consecutivas. Se guarda
  /// sólo como control cruzado: si se despega mucho de [metros], algo anda
  /// mal en la señal.
  final double metrosHaversine;

  final int muestrasUsadas;
  final int muestrasDescartadas;

  /// Cuántas veces hubo que cortar por un hueco mayor al tolerado.
  final int cortes;

  /// Milisegundos efectivamente integrados (no incluye los huecos cortados).
  final int msIntegrados;

  const ResultadoOdometria({
    required this.metros,
    required this.metrosHaversine,
    required this.muestrasUsadas,
    required this.muestrasDescartadas,
    required this.cortes,
    required this.msIntegrados,
  });

  double get kilometros => metros / 1000.0;

  /// Diferencia relativa entre los dos métodos. Por encima de ~0,15 conviene
  /// mirar el tramo con desconfianza.
  double get discrepancia {
    if (metros <= 0) return 0.0;
    return (metrosHaversine - metros).abs() / metros;
  }
}

const double _radioTierraM = 6371008.8; // radio medio IUGG, en metros

/// Distancia de círculo máximo entre dos muestras, en metros.
double haversine(Muestra a, Muestra b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final lat1 = _rad(a.lat);
  final lat2 = _rad(b.lat);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * _radioTierraM * math.asin(math.min(1.0, math.sqrt(h)));
}

double _rad(double grados) => grados * math.pi / 180.0;

bool _aceptable(Muestra m, CriteriosGps c) {
  if (!m.velocidad.isFinite || m.velocidad < 0) return false;
  if (!m.precision.isFinite || m.precision < 0) return false;
  if (!m.lat.isFinite || !m.lon.isFinite) return false;
  if (m.lat.abs() > 90 || m.lon.abs() > 180) return false;
  if (m.precision > c.precisionMaxima) return false;
  if (m.velocidad > c.velocidadMaxima) return false;
  final pv = m.precisionVel;
  if (pv != null && (!pv.isFinite || pv > c.precisionVelMaxima)) return false;
  return true;
}

double _velocidadEfectiva(Muestra m, CriteriosGps c) =>
    m.velocidad < c.velocidadMinima ? 0.0 : m.velocidad;

/// Integra la distancia recorrida a partir de la velocidad Doppler.
///
/// Por qué no se suman haversines entre puntos consecutivos, que es lo que
/// hace casi todo el mundo: el ruido de posición **siempre suma y nunca
/// resta**. Un vehículo detenido con el receptor saltando dos metros acumula
/// kilómetros que no existieron. La velocidad que informa el receptor no sale
/// de diferenciar posiciones sino del corrimiento Doppler de la portadora, y
/// su error es de otro orden de magnitud.
///
/// La regla del trapecio entre muestras consecutivas es suficiente: a 1 Hz el
/// error de cuadratura frente a la aceleración real de una camioneta es muy
/// inferior al del propio sensor.
ResultadoOdometria integrar(
  List<Muestra> muestras, {
  CriteriosGps criterios = const CriteriosGps(),
}) {
  if (muestras.length < 2) {
    return ResultadoOdometria(
      metros: 0,
      metrosHaversine: 0,
      muestrasUsadas: muestras.where((m) => _aceptable(m, criterios)).length,
      muestrasDescartadas: muestras
          .where((m) => !_aceptable(m, criterios))
          .length,
      cortes: 0,
      msIntegrados: 0,
    );
  }

  // Se ordena defensivamente: las muestras pueden llegar desordenadas de un
  // stream con buffer, y una diferencia de tiempo negativa daría distancia
  // negativa sin que nada avise.
  final ordenadas = List<Muestra>.from(muestras)
    ..sort((a, b) => a.t.compareTo(b.t));

  double metros = 0;
  double metrosHav = 0;
  int usadas = 0, descartadas = 0, cortes = 0, msIntegrados = 0;
  Muestra? ant;

  for (final m in ordenadas) {
    if (!_aceptable(m, criterios)) {
      descartadas++;
      continue;
    }
    if (ant != null) {
      final dt = m.t - ant.t;
      if (dt <= 0) {
        // Dos muestras con el mismo sello de tiempo, o un reloj que retrocedió.
        descartadas++;
        continue;
      }
      if (dt > criterios.huecoMaximoMs) {
        cortes++;
      } else {
        final v0 = _velocidadEfectiva(ant, criterios);
        final v1 = _velocidadEfectiva(m, criterios);
        metros += (v0 + v1) / 2.0 * dt / 1000.0;
        metrosHav += haversine(ant, m);
        msIntegrados += dt;
      }
    }
    usadas++;
    ant = m;
  }

  return ResultadoOdometria(
    metros: metros,
    metrosHaversine: metrosHav,
    muestrasUsadas: usadas,
    muestrasDescartadas: descartadas,
    cortes: cortes,
    msIntegrados: msIntegrados,
  );
}
