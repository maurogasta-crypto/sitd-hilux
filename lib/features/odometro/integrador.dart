import 'dart:math' as math;

import 'muestra.dart';

/// Por qué se descartó una muestra.
///
/// **Existe porque «descartadas: 412» no se puede diagnosticar.** Cuatrocientas
/// doce por precisión mala y cuatrocientas doce por llegar sin velocidad son
/// dos problemas completamente distintos —uno se arregla saliendo a cielo
/// abierto y el otro dándole permiso de ubicación PRECISA— y hasta que el
/// motivo no se guardó, las dos se veían igual.
enum MotivoDescarte {
  /// El error de posición informado supera el tolerado.
  precisionMala,

  /// El error de velocidad informado supera el tolerado.
  precisionVelMala,

  /// Más rápido de lo que puede ir una camioneta: rebote de señal o salto del
  /// receptor.
  velocidadImplausible,

  /// Números que no son números, o coordenadas fuera del mundo.
  datoInvalido,

  /// Dos muestras con el mismo sello de tiempo, o un reloj que retrocedió.
  relojParaAtras,
}

/// Umbrales con los que se acepta o se descarta una muestra del GPS.
///
/// Los valores por defecto son conservadores a propósito: es preferible
/// descartar una muestra buena que integrar una mala, porque el error de
/// distancia no se compensa —siempre suma.
class CriteriosGps {
  /// Error horizontal máximo tolerado, en metros.
  ///
  /// **Cincuenta metros, y es a propósito que sea generoso.** Acá no se integra
  /// la posición sino la velocidad Doppler, que es un dato aparte y mucho mejor:
  /// un receptor puede estar dando una posición con 40 m de error y una
  /// velocidad con 0,2 m/s. Filtrar con la vara de la posición tiraría muestras
  /// de velocidad perfectamente buenas — y un teléfono apoyado en el tablero,
  /// bajo un parabrisas con película metalizada, anda justo en esa zona. Lo
  /// único que se degrada con este número alto es el haversine de control.
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
    this.precisionMaxima = 50.0,
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

  /// Cuántas se descartaron por cada motivo. Es lo que convierte un número
  /// inútil en un diagnóstico.
  final Map<MotivoDescarte, int> descartes;

  /// La precisión típica de las que se cayeron por precisión, en metros. Sirve
  /// para distinguir «está bajo un techo» (30-60 m) de «el teléfono está en
  /// ubicación APROXIMADA» (cientos o miles).
  final double precisionTipicaDescartada;

  const ResultadoOdometria({
    required this.metros,
    required this.metrosHaversine,
    required this.muestrasUsadas,
    required this.muestrasDescartadas,
    required this.cortes,
    required this.msIntegrados,
    this.descartes = const {},
    this.precisionTipicaDescartada = 0,
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

/// Devuelve `null` si la muestra sirve, o el motivo por el que no.
MotivoDescarte? porQueNoSirve(Muestra m, CriteriosGps c) {
  final pv = m.precisionVel;
  final invalida =
      !m.velocidad.isFinite ||
      m.velocidad < 0 ||
      !m.precision.isFinite ||
      m.precision < 0 ||
      !m.lat.isFinite ||
      !m.lon.isFinite ||
      m.lat.abs() > 90 ||
      m.lon.abs() > 180 ||
      (pv != null && !pv.isFinite);
  if (invalida) return MotivoDescarte.datoInvalido;
  if (m.precision > c.precisionMaxima) return MotivoDescarte.precisionMala;
  if (m.velocidad > c.velocidadMaxima) {
    return MotivoDescarte.velocidadImplausible;
  }
  if (pv != null && pv > c.precisionVelMaxima) {
    return MotivoDescarte.precisionVelMala;
  }
  return null;
}

double _velocidadEfectiva(Muestra m, CriteriosGps c) =>
    m.velocidad < c.velocidadMinima ? 0.0 : m.velocidad;

/// Acumulador incremental: la misma integración, pero muestra por muestra.
///
/// Existe porque en vivo no hay lista. El servicio de odometría recibe una
/// muestra por segundo y tiene que poder decir en cualquier momento cuántos
/// kilómetros van, sin volver a recorrer todo lo anterior.
///
/// **Es el mismo cálculo que [integrar], y eso está probado**: el banco
/// comprueba que alimentar el acumulador muestra por muestra da exactamente
/// lo mismo que integrar la lista entera. Si alguna vez se toca uno de los
/// dos, esa prueba es la que avisa — de hecho [integrar] no es más que este
/// acumulador con la lista ordenada de antemano.
///
/// La diferencia que sí importa: acá **no se puede ordenar**. Las muestras
/// llegan cuando llegan. Una que venga con el reloj para atrás se descarta,
/// que es lo mismo que hace [integrar] con dos sellos de tiempo iguales.
class Acumulador {
  final CriteriosGps criterios;

  double _metros = 0;
  double _metrosHav = 0;
  int _usadas = 0;
  int _descartadas = 0;
  int _cortes = 0;
  int _msIntegrados = 0;
  Muestra? _ant;
  final Map<MotivoDescarte, int> _descartes = {};
  double _sumaPrecisionMala = 0;
  int _nPrecisionMala = 0;
  MotivoDescarte? _ultimoMotivo;

  Acumulador({this.criterios = const CriteriosGps()});

  /// La última muestra aceptada, o `null` si todavía no hubo ninguna.
  Muestra? get ultima => _ant;

  /// Por qué se cayó la última que no sirvió. Es lo que la pantalla necesita
  /// para decir algo útil mientras el número de kilómetros no se mueve.
  MotivoDescarte? get ultimoMotivo => _ultimoMotivo;

  /// Agrega una muestra. Devuelve `true` si se aceptó.
  ///
  /// Un `false` no es un error: con el receptor recién encendido, o bajo un
  /// techo, es lo normal durante los primeros segundos. Lo que no es normal es
  /// que sigan siendo todas `false` con el vehículo en movimiento, y por eso
  /// la cuenta de descartadas se muestra en pantalla.
  bool agregar(Muestra m) {
    final motivo = porQueNoSirve(m, criterios);
    if (motivo != null) {
      _anotarDescarte(motivo, m);
      return false;
    }
    final ant = _ant;
    if (ant != null) {
      final dt = m.t - ant.t;
      if (dt <= 0) {
        _anotarDescarte(MotivoDescarte.relojParaAtras, m);
        return false;
      }
      if (dt > criterios.huecoMaximoMs) {
        // Un túnel, o el receptor que se quedó sin cielo. No se puentea: se
        // corta. Integrar a través del hueco inventa una línea recta.
        _cortes++;
      } else {
        final v0 = _velocidadEfectiva(ant, criterios);
        final v1 = _velocidadEfectiva(m, criterios);
        _metros += (v0 + v1) / 2.0 * dt / 1000.0;
        _metrosHav += haversine(ant, m);
        _msIntegrados += dt;
      }
    }
    _usadas++;
    _ant = m;
    _ultimoMotivo = null;
    return true;
  }

  void _anotarDescarte(MotivoDescarte motivo, Muestra m) {
    _descartadas++;
    _ultimoMotivo = motivo;
    _descartes[motivo] = (_descartes[motivo] ?? 0) + 1;
    if (motivo == MotivoDescarte.precisionMala && m.precision.isFinite) {
      _sumaPrecisionMala += m.precision;
      _nPrecisionMala++;
    }
  }

  ResultadoOdometria get resultado => ResultadoOdometria(
    metros: _metros,
    metrosHaversine: _metrosHav,
    muestrasUsadas: _usadas,
    muestrasDescartadas: _descartadas,
    cortes: _cortes,
    msIntegrados: _msIntegrados,
    descartes: Map.unmodifiable(_descartes),
    precisionTipicaDescartada: _nPrecisionMala == 0
        ? 0
        : _sumaPrecisionMala / _nPrecisionMala,
  );
}

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
///
/// Es [Acumulador] con la lista ordenada de antemano, y no una segunda copia
/// del cálculo: se ordena defensivamente porque las muestras pueden llegar
/// desordenadas de un stream con buffer, y una diferencia de tiempo negativa
/// daría distancia negativa sin que nada avise.
ResultadoOdometria integrar(
  List<Muestra> muestras, {
  CriteriosGps criterios = const CriteriosGps(),
}) {
  final ordenadas = List<Muestra>.from(muestras)
    ..sort((a, b) => a.t.compareTo(b.t));
  final acumulador = Acumulador(criterios: criterios);
  for (final m in ordenadas) {
    acumulador.agregar(m);
  }
  return acumulador.resultado;
}
