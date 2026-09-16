import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fuente.dart';
import 'integrador.dart';
import 'muestra.dart';
import 'registro.dart';

/// Lo que hay que saber del viaje en curso, que es lo que se dibuja.
@immutable
class EstadoViaje {
  /// El viaje abierto, o `null` si no hay ninguno.
  final int? viaje;

  /// Cuándo empezó, en milisegundos desde la época.
  final int? inicio;

  /// `true` mientras el GPS esté entregando.
  final bool midiendo;

  final ResultadoOdometria odometria;

  /// La última muestra aceptada. De acá sale la velocidad de la pantalla.
  final Muestra? ultima;

  /// Cuántas posiciones llegaron sin velocidad Doppler. Ver [Lectura].
  final int sinDoppler;

  /// Por qué no se está midiendo, cuando corresponde decirlo.
  final Disponibilidad? problema;

  const EstadoViaje({
    this.viaje,
    this.inicio,
    this.midiendo = false,
    this.odometria = const ResultadoOdometria(
      metros: 0,
      metrosHaversine: 0,
      muestrasUsadas: 0,
      muestrasDescartadas: 0,
      cortes: 0,
      msIntegrados: 0,
    ),
    this.ultima,
    this.sinDoppler = 0,
    this.problema,
  });

  bool get hayViaje => viaje != null;
  double get kilometros => odometria.kilometros;

  /// Velocidad en km/h de la última muestra, o `null` si todavía no hubo
  /// ninguna. **No se inventa un cero**: «todavía no sé» y «está quieta» son
  /// cosas distintas y se muestran distinto.
  double? get velocidadKmh {
    final m = ultima;
    return m == null ? null : m.velocidad * 3.6;
  }

  EstadoViaje copiar({
    int? viaje,
    int? inicio,
    bool? midiendo,
    ResultadoOdometria? odometria,
    Muestra? ultima,
    int? sinDoppler,
    Disponibilidad? problema,
    bool limpiarViaje = false,
    bool limpiarProblema = false,
  }) => EstadoViaje(
    viaje: limpiarViaje ? null : (viaje ?? this.viaje),
    inicio: limpiarViaje ? null : (inicio ?? this.inicio),
    midiendo: midiendo ?? this.midiendo,
    odometria: odometria ?? this.odometria,
    ultima: ultima ?? this.ultima,
    sinDoppler: sinDoppler ?? this.sinDoppler,
    problema: limpiarProblema ? null : (problema ?? this.problema),
  );
}

/// El que junta las tres piezas: la fuente entrega, el acumulador integra y el
/// registro guarda.
///
/// **Lo que no hace, a propósito: no decide solo cuándo empieza un viaje.** Se
/// evaluó arrancar al detectar movimiento y se dejó para más adelante, con la
/// línea base ya medida. Un viaje que arranca solo cuando no correspondía
/// ensucia el factor de neumáticos y las estadísticas de consumo, y hoy no hay
/// con qué distinguir «salió a la ruta» de «la movieron en el taller». El
/// botón no se equivoca.
class ServicioOdometria {
  final RegistroDeViajes registro;
  final FuenteDeMuestras fuente;
  final CriteriosGps criterios;

  /// El reloj, inyectable: el banco de pruebas no espera un segundo de verdad.
  final int Function() ahora;

  /// Cada cuántos puntos se vuelca el total a la fila del viaje. Los puntos se
  /// guardan siempre uno por uno; esto es sólo el resumen, que se puede
  /// recalcular desde los puntos y por eso no urge.
  final int cadaCuantosVuelca;

  final ValueNotifier<EstadoViaje> estado = ValueNotifier(const EstadoViaje());

  Acumulador _acumulador;
  StreamSubscription<Lectura>? _suscripcion;
  int _desdeElUltimoVuelco = 0;

  ServicioOdometria({
    required this.registro,
    required this.fuente,
    this.criterios = const CriteriosGps(),
    int Function()? reloj,
    this.cadaCuantosVuelca = 10,
  }) : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch),
       _acumulador = Acumulador(criterios: criterios);

  /// Busca un viaje que haya quedado abierto y lo deja listo para seguir.
  ///
  /// Se llama al arrancar la aplicación. Si el sistema la mató en medio de un
  /// viaje —MIUI lo hace—, los puntos están guardados y el total se rehace
  /// integrándolos de nuevo. No se pierde un metro.
  Viaje? retomarPendiente() {
    final v = registro.abierto;
    if (v == null) return null;
    _acumulador = Acumulador(criterios: criterios);
    for (final m in registro.puntosDe(v.id)) {
      _acumulador.agregar(m);
    }
    estado.value = EstadoViaje(
      viaje: v.id,
      inicio: v.inicio,
      midiendo: false,
      odometria: _acumulador.resultado,
      ultima: _acumulador.ultima,
    );
    return v;
  }

  /// Pide permiso, abre o retoma el viaje y se engancha al GPS.
  ///
  /// Devuelve `false` si no se pudo, y en ese caso el motivo queda en
  /// `estado.value.problema` para que la pantalla lo diga con palabras.
  Future<bool> arrancar({double? odoTablero}) async {
    if (estado.value.midiendo) return true;

    final disponible = await fuente.preparar();
    if (!disponible.puedeArrancar) {
      estado.value = estado.value.copiar(midiendo: false, problema: disponible);
      return false;
    }

    if (!estado.value.hayViaje) {
      final pendiente = retomarPendiente();
      if (pendiente == null) {
        final inicio = ahora();
        final id = registro.abrir(inicio: inicio, odoTablero: odoTablero);
        _acumulador = Acumulador(criterios: criterios);
        estado.value = EstadoViaje(viaje: id, inicio: inicio);
      }
    }

    _desdeElUltimoVuelco = 0;
    _suscripcion = fuente.lecturas.listen(
      _recibir,
      onError: (Object e) {
        estado.value = estado.value.copiar(
          midiendo: false,
          problema: Disponibilidad(MotivoGps.falla, detalle: '$e'),
        );
      },
    );
    estado.value = estado.value.copiar(midiendo: true, limpiarProblema: true);
    return true;
  }

  void _recibir(Lectura lectura) {
    final viaje = estado.value.viaje;
    if (viaje == null) return;

    final m = lectura.muestra;
    if (m == null) {
      estado.value = estado.value.copiar(
        sinDoppler: estado.value.sinDoppler + 1,
      );
      return;
    }

    final aceptada = _acumulador.agregar(m);
    if (aceptada) {
      registro.guardarPunto(viaje, m);
      if (++_desdeElUltimoVuelco >= cadaCuantosVuelca) {
        registro.actualizar(viaje, _acumulador.resultado);
        _desdeElUltimoVuelco = 0;
      }
    }
    estado.value = estado.value.copiar(
      odometria: _acumulador.resultado,
      ultima: _acumulador.ultima,
    );
  }

  /// Corta la entrega de muestras sin cerrar el viaje. Es lo que hace falta
  /// para una parada larga: se retoma con [arrancar] y el viaje sigue siendo
  /// el mismo.
  Future<void> pausar() async {
    await _suscripcion?.cancel();
    _suscripcion = null;
    await fuente.detener();
    final viaje = estado.value.viaje;
    if (viaje != null) registro.actualizar(viaje, _acumulador.resultado);
    estado.value = estado.value.copiar(midiendo: false);
  }

  /// Cierra el viaje: deja el total escrito y suelta el GPS.
  Future<Viaje?> terminar({double? odoTablero}) async {
    final viaje = estado.value.viaje;
    await _suscripcion?.cancel();
    _suscripcion = null;
    await fuente.detener();
    if (viaje == null) {
      estado.value = const EstadoViaje();
      return null;
    }
    registro.cerrar(
      viaje,
      fin: ahora(),
      odometria: _acumulador.resultado,
      odoTablero: odoTablero,
    );
    final cerrado = registro.porId(viaje);
    _acumulador = Acumulador(criterios: criterios);
    _desdeElUltimoVuelco = 0;
    estado.value = const EstadoViaje();
    return cerrado;
  }

  void cerrarRecursos() {
    _suscripcion?.cancel();
    estado.dispose();
  }
}
