import '../../core/db/base.dart';
import '../../core/db/esquema.dart';
import '../combustible/registro_cargas.dart';
import '../odometro/registro.dart';
import '../vibracion/registro_vibracion.dart';

/// Cuánto sale del teléfono.
///
/// **Son dos cosas distintas y no se pueden confundir**, porque una se puede
/// mandar por un chat y la otra no.
enum Alcance {
  /// Todo menos **dónde estuvo la camioneta**. Lleva los kilómetros, los
  /// contadores, los motivos de descarte, un resumen estadístico de las
  /// muestras y los vectores de vibración: alcanza para diagnosticar y para
  /// ajustar el código. Ninguna latitud, ninguna longitud.
  paraDesarrollo,

  /// Todo, con el recorrido punto por punto. **Es el respaldo de Mauro y no va
  /// a ningún chat**: la base guarda dónde estuvo la camioneta minuto a
  /// minuto, y eso no se pega en ningún lado.
  respaldoCompleto,
}

/// Arma el reporte como un mapa listo para serializar a JSON.
///
/// Por qué un mapa y no una clase con `toJson`: lo que se manda tiene que
/// poder leerse con los ojos y cambiar de forma entre tandas sin romper nada
/// del otro lado. Es un archivo para diagnosticar, no un protocolo.
Map<String, dynamic> armarReporte({
  required Base base,
  required RegistroDeViajes viajes,
  required RegistroDeCargas cargas,
  required RegistroDeVibracion vibraciones,
  required Alcance alcance,
  required String sello,
  required int ahora,
  int cuantosViajes = 20,
}) {
  final conRecorrido = alcance == Alcance.respaldoCompleto;
  final losViajes = viajes.ultimos(conRecorrido ? 1000 : cuantosViajes);
  final porViaje = vibraciones.porViaje();

  return {
    'reporte': conRecorrido ? 'respaldo-completo' : 'para-desarrollo',
    'generado': ahora,
    'app': {
      'sello': sello,
      'esquema': versionEsquema,
      'esquemaDeLaBase': base.version,
    },
    // Lo que hace falta para saber si un número raro es del código o del
    // aparato. Sin esto, «me da 45 Hz» no se puede comparar con nada.
    'aparato': {'tablas': base.tablas},
    'sinRecorrido': !conRecorrido,
    'viajes': [
      for (final v in losViajes)
        {
          'id': v.id,
          'inicio': v.inicio,
          'fin': v.fin,
          'metros': v.metros,
          'metrosHaversine': v.metrosHaversine,
          'cortes': v.cortes,
          'muestras': v.muestras,
          'descartadas': v.descartadas,
          'sinDoppler': v.sinDoppler,
          'precisionDescartada': v.precisionDescartada,
          'motivos': v.motivos,
          'odoTableroIni': v.odoTableroIni,
          'odoTableroFin': v.odoTableroFin,
          // El resumen va SIEMPRE, y es lo que convierte un viaje en cero en
          // algo diagnosticable: qué velocidades y qué precisiones llegaron,
          // sin decir dónde.
          'muestrasResumen': _resumen(viajes.puntosDe(v.id)),
          if (conRecorrido)
            'puntos': [
              for (final m in viajes.puntosDe(v.id))
                {
                  't': m.t,
                  'lat': m.lat,
                  'lon': m.lon,
                  'alt': m.alt,
                  'velocidad': m.velocidad,
                  'precision': m.precision,
                  'precisionVel': m.precisionVel,
                },
            ],
          'vibraciones': [
            for (final w in porViaje[v.id] ?? const [])
              {
                't': w.t,
                'cubeta': w.cubeta,
                'hz': w.hz,
                'muestras': w.muestras,
                'rms': w.rms,
                'pico': w.pico,
                'bandas': w.bandas,
              },
          ],
        },
    ],
    'cargas': [
      for (final c in cargas.todas())
        {
          't': c.t,
          'litros': c.litros,
          'costo': c.costo,
          'moneda': c.moneda,
          'odoTablero': c.odoTablero,
          'tanqueLleno': c.tanqueLleno,
          'estacion': c.estacion,
          'notas': c.notas,
        },
    ],
    'ajustes': {'litrosDelTanque': cargas.litrosDelTanque},
  };
}

/// Estadística de las muestras de un viaje, **sin una sola coordenada**.
///
/// Mediana y extremos, no promedio: un solo salto del receptor mueve el
/// promedio de la precisión y deja de contar lo que pasó el resto del viaje.
Map<String, dynamic> _resumen(List<dynamic> puntos) {
  if (puntos.isEmpty) {
    return {'cuantas': 0};
  }
  final velocidades = <double>[];
  final precisiones = <double>[];
  final tiempos = <int>[];
  for (final p in puntos) {
    velocidades.add(p.velocidad as double);
    precisiones.add(p.precision as double);
    tiempos.add(p.t as int);
  }
  velocidades.sort();
  precisiones.sort();

  // Cadencia: cada cuánto llegó una muestra aceptada. Un número muy arriba de
  // un segundo dice que el receptor se está quedando sin cielo, o que el
  // sistema está durmiendo la aplicación.
  double? cadencia;
  if (tiempos.length > 1) {
    final lapso = tiempos.last - tiempos.first;
    if (lapso > 0) cadencia = lapso / (tiempos.length - 1) / 1000;
  }

  return {
    'cuantas': puntos.length,
    'velocidadMs': _tresNumeros(velocidades),
    'precisionM': _tresNumeros(precisiones),
    'segundosEntreMuestras': cadencia,
  };
}

Map<String, double> _tresNumeros(List<double> ordenados) => {
  'min': ordenados.first,
  'mediana': _mediana(ordenados),
  'max': ordenados.last,
};

double _mediana(List<double> ordenados) {
  final n = ordenados.length;
  if (n.isOdd) return ordenados[n ~/ 2];
  return (ordenados[n ~/ 2 - 1] + ordenados[n ~/ 2]) / 2;
}
