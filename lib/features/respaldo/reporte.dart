import '../../core/bitacora.dart';
import '../../core/db/base.dart';
import '../../core/registro_eventos.dart';
import '../../core/db/esquema.dart';
import '../combustible/registro_cargas.dart';
import '../odometro/registro.dart';
import '../sensores/satelites.dart';
import '../vibracion/analisis.dart';
import '../vibracion/cobertura.dart';
import '../vibracion/espectro.dart';
import '../vibracion/registro_vibracion.dart';
import '../vibracion/ventana.dart';

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

/// Todo lo que hace falta para volver a correr el análisis afuera del
/// teléfono, y para entender un vector de vibración sin adivinar.
///
/// **Son cuatro cosas y las cuatro faltaban.** Con los vectores solos no se
/// puede: hacen falta los parámetros —sin ellos los números no tienen
/// unidades—, la línea base —que es literalmente lo que el sistema considera
/// normal—, lo que concluyó, y la cobertura, que es la que distingue «está
/// todo bien» de «todavía no aprendió nada».
Map<String, dynamic> _analisis(
  Map<int, List<VentanaVibracion>> porViaje,
  // Del más nuevo al más viejo: es el orden que pide la histéresis. Los TRES
  // últimos, no tres cualesquiera.
  List<int> ultimosViajes,
) {
  final base = lineaBase(porViaje);
  final ventanasPorCubeta = <int, int>{};
  for (final ventanas in porViaje.values) {
    for (final v in ventanas) {
      ventanasPorCubeta[v.cubeta] = (ventanasPorCubeta[v.cubeta] ?? 0) + 1;
    }
  }
  final encontradas = anomalias(porViaje, ultimosViajes);

  return {
    // Las reglas con las que se calculó todo lo de abajo. Van en el reporte y
    // no en la documentación porque un reporte viejo tiene que poder leerse
    // aunque las reglas hayan cambiado desde entonces.
    'parametros': {
      'bordesHz': bordesHz,
      'cantidadDeBandas': cantidadDeBandas,
      'anchoDeCubetaKmh': anchoDeCubeta,
      'velocidadMinimaKmh': velocidadMinimaKmh,
      'cubetaMaxima': cubetaMaxima,
      'segundosPorVentana': segundosPorVentana,
      'ventanasParaLineaBase': ventanasParaLineaBase,
      'umbralDeDesvio': umbralDeDesvio,
      'viajesSeguidosParaAvisar': viajesSeguidosParaAvisar,
      'diametroDeRuedaM': diametroDeRuedaM,
      // Qué se compara. Desde `sitd-33` la línea base y las anomalías son la
      // FORMA del espectro —la parte de la vibración que se lleva cada banda,
      // sumando 1—, no la energía. Va escrito en el reporte porque un reporte
      // viejo tiene que poder leerse: sus `mediana` son energías, los nuevos
      // son proporciones, y sin esta línea no habría cómo distinguirlos.
      'comparaLa': 'forma',
    },
    // Cuánto sabe de cada velocidad. Incluye las cubetas vacías: una cubeta
    // que falta dice a qué velocidad hay que salir a andar.
    'cobertura': [
      for (final c in cobertura(ventanasPorCubeta))
        {
          'cubeta': c.cubeta,
          'rango': nombreDeCubeta(c.cubeta),
          'ventanas': c.ventanas,
          'necesarias': c.necesarias,
          'lista': c.lista,
          'segundosQueFaltan': c.segundosQueFaltan,
          // En qué banda caería un defecto de rueda a esta velocidad. Es una
          // ayuda para leer el espectro, no una medición.
          'bandaDeLaRueda': bandaDeLaRueda(velocidadTipicaDe(c.cubeta)),
          'vueltasPorSegundo': vueltasPorSegundo(velocidadTipicaDe(c.cubeta)),
        },
    ],
    // Lo que considera normal, por cubeta y por banda.
    'lineaBase': [
      for (final b in base.values)
        {
          'cubeta': b.cubeta,
          'rango': nombreDeCubeta(b.cubeta),
          'ventanas': b.ventanas,
          'suficiente': b.suficiente,
          'mediana': b.mediana,
          'mad': b.mad,
        },
    ],
    // Lo que concluyó: sólo lo que se repitió lo suficiente como para decirlo.
    'anomalias': [
      for (final a in encontradas)
        {
          'cubeta': a.cubeta,
          'rango': nombreDeCubeta(a.cubeta),
          'banda': a.banda,
          'bandaHz': a.ultimo.rango,
          'z': a.z,
          'viajes': a.viajes,
          'ahora': a.ultimo.ahora,
          'normal': a.ultimo.normal,
        },
    ],
  };
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

  /// La bitácora en disco. Es la que vale: la de memoria se pierde al cerrar
  /// la aplicación, y un reporte se genera horas después del viaje.
  RegistroDeEventos? eventos,
  Bitacora? registro,
  EstadoSatelites? satelites,

  /// Cuando está, el reporte lleva **ese** viaje y ningún otro. Es lo que usa
  /// la cola de subida: un documento por viaje.
  int? soloElViaje,
}) {
  final conRecorrido = alcance == Alcance.respaldoCompleto;
  // **`soloElViaje` no es una comodidad: sin él la subida estaba mal.** La
  // cola sube el viaje 1 mientras el teléfono ya hizo el 2 y el 3, y
  // `ultimos(1)` devuelve el más nuevo — o sea que los tres documentos habrían
  // llevado los datos del último. Encontrado releyendo, antes de que subiera
  // un solo reporte.
  final losViajes = soloElViaje != null
      ? [?viajes.porId(soloElViaje)]
      : viajes.ultimos(conRecorrido ? 1000 : cuantosViajes);
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
    // Lo que ve la ANTENA, que es lo único que separa «el receptor no fijó
    // todavía» de «el receptor no ve nada». Va en los dos alcances: no lleva
    // una sola coordenada, sólo cuántos satélites y con cuánta señal.
    'satelites': (satelites ?? const EstadoSatelites()).aMapa(),
    // El registro de lo que la aplicación le pidió al sistema y de lo que el
    // sistema contestó. Lo pidió Mauro el 2026-09-16, y sirve sobre todo para
    // lo que pasa MIENTRAS SE MANEJA, que es cuando nadie puede mirar la
    // pantalla. Nunca lleva coordenadas: ver `bitacora.dart`.
    'bitacora': eventos?.ultimos() ?? (registro ?? bitacora).aMapa(),
    // Lo que el sistema APRENDIÓ y con qué reglas. Sin esto, los vectores de
    // vibración son listas de números sin unidades: no se puede saber qué
    // considera normal, ni por qué avisó, ni si todavía no aprendió nada.
    'analisis': _analisis(porViaje, vibraciones.ultimosViajes()),
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
