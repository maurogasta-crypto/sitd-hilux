import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/bitacora.dart';
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

  /// La precisión de la última posición que llegó sin velocidad, o `null`.
  /// Es lo que separa «ubicación de red» de «satélite sin resolver todavía».
  final double? precisionSinDoppler;

  /// Cuántas posiciones llegaron sin velocidad Doppler. Ver [Lectura].
  final int sinDoppler;

  /// La última posición que entregó el receptor, haya servido o no.
  ///
  /// **Es distinta de [ultima], y la diferencia es el diagnóstico entero.**
  /// `ultima` es la última que se pudo usar; ésta es la última que llegó. Si
  /// hay una cruda nueva cada segundo y `ultima` no se mueve, el GPS está
  /// hablando y el filtro las está tirando — que no se parece en nada a un
  /// receptor callado.
  final Muestra? ultimaCruda;

  /// Por qué se descartó la última, si se descartó.
  final MotivoDescarte? ultimoMotivo;

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
    this.precisionSinDoppler,
    this.ultimaCruda,
    this.ultimoMotivo,
    this.problema,
  });

  bool get hayViaje => viaje != null;
  double get kilometros => odometria.kilometros;

  /// Qué está pasando con la señal mientras todavía no hay un solo kilómetro,
  /// o `null` cuando no hay nada que decir.
  ///
  /// **Existe por un viaje real de 13 segundos que dio 0,0 km.** Adentro de una
  /// casa el receptor no fija satélites, así que la pantalla mostraba cero y
  /// nada más: «el GPS todavía no ve el cielo» y «la aplicación no anda» se
  /// veían exactamente igual. Un estado sin explicación es un error invisible
  /// (`PROTOCOLO-INTERFAZ.md` § 7.2), y acá el precio es que alguien crea que
  /// lo que está roto es el programa.
  String? get estadoDeLaSenal {
    if (!midiendo) return null;
    if (odometria.muestrasUsadas > 0) return null;

    final descartes = odometria.descartes;
    if (descartes.isNotEmpty) {
      final motivo = descartes.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final cuantas = odometria.muestrasDescartadas;
      switch (motivo) {
        case MotivoDescarte.precisionMala:
          final p = odometria.precisionTipicaDescartada;
          // Arriba de 200 m no es «mala señal»: es el teléfono entregando
          // ubicación APROXIMADA, que se elige en el diálogo del permiso y
          // después no se nota por ningún lado.
          return p > 200
              ? 'Llegan posiciones con ${p.toStringAsFixed(0)} m de error. '
                    'Eso no es mala señal: es ubicación aproximada. Hay que '
                    'darle permiso de ubicación PRECISA en Ajustes → '
                    'Aplicaciones → SITD Hilux → Permisos → Ubicación.'
              : 'Llegan posiciones pero con ${p.toStringAsFixed(0)} m de '
                    'error, y se descartan ($cuantas hasta ahora). Con cielo '
                    'abierto suele bajar en un minuto.';
        case MotivoDescarte.precisionVelMala:
          return 'El receptor da velocidad, pero dice que no le cree: su '
              'propio margen de error es más grande de lo tolerado. Pasa '
              'mientras está fijando satélites.';
        case MotivoDescarte.velocidadImplausible:
          return 'Llegan velocidades imposibles para una camioneta, así que '
              'se descartan. Es un rebote de señal, típico entre edificios.';
        case MotivoDescarte.relojParaAtras:
          return 'Llegan muestras con el reloj repetido o para atrás. Es raro: '
              'anotalo y contámelo.';
        case MotivoDescarte.datoInvalido:
          return 'El receptor está entregando datos que no son números. Es '
              'raro: anotalo y contámelo.';
      }
    }

    if (sinDoppler > 0) {
      // Llegan posiciones: el receptor NO está callado. Lo que falta es la
      // velocidad, y la precisión dice de qué clase son — que es la diferencia
      // entre esperar y no esperar.
      final p = precisionSinDoppler;
      if (p != null && p > 100) {
        return 'Llegaron $sinDoppler posiciones, pero ninguna trae velocidad '
            'y todas vienen con ${p.toStringAsFixed(0)} m de error. Eso no es '
            'el satélite: es ubicación de red —wifi y torres de celular—, que '
            'nunca trae velocidad. El receptor GPS todavía no fijó. A cielo '
            'abierto y quieto puede tardar varios minutos si el teléfono '
            'estuvo lejos de acá la última vez que lo usó.';
      }
      return 'Llegaron $sinDoppler posiciones y ninguna trae velocidad '
          '${p == null ? "" : "(${p.toStringAsFixed(0)} m de error) "}'
          'todavía. El receptor está hablando: es lo normal mientras termina '
          'de fijar satélites.';
    }
    return 'Esperando la primera muestra del GPS. Con cielo abierto tarda '
        'entre treinta segundos y un minuto; adentro de una casa puede no '
        'llegar nunca.';
  }

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
    double? precisionSinDoppler,
    Muestra? ultimaCruda,
    MotivoDescarte? ultimoMotivo,
    Disponibilidad? problema,
    bool limpiarViaje = false,
    bool limpiarProblema = false,
    bool limpiarMotivo = false,
  }) => EstadoViaje(
    viaje: limpiarViaje ? null : (viaje ?? this.viaje),
    inicio: limpiarViaje ? null : (inicio ?? this.inicio),
    midiendo: midiendo ?? this.midiendo,
    odometria: odometria ?? this.odometria,
    ultima: ultima ?? this.ultima,
    sinDoppler: sinDoppler ?? this.sinDoppler,
    precisionSinDoppler: precisionSinDoppler ?? this.precisionSinDoppler,
    ultimaCruda: ultimaCruda ?? this.ultimaCruda,
    ultimoMotivo: limpiarMotivo ? null : (ultimoMotivo ?? this.ultimoMotivo),
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

    bitacora.anotar(Origen.viaje, 'Tocaron «Empezar el viaje».');
    final disponible = await fuente.preparar();
    if (!disponible.puedeArrancar) {
      bitacora.anotar(
        Origen.viaje,
        'No se pudo arrancar: ${disponible.mensaje}',
      );
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
    bitacora.anotar(
      Origen.viaje,
      'Viaje ${estado.value.viaje} midiendo, suscripto al GPS.',
    );
    return true;
  }

  void _recibir(Lectura lectura) {
    final viaje = estado.value.viaje;
    if (viaje == null) return;

    final m = lectura.muestra;
    if (m == null) {
      estado.value = estado.value.copiar(
        sinDoppler: estado.value.sinDoppler + 1,
        precisionSinDoppler: lectura.precisionCruda,
      );
      return;
    }

    final aceptada = _acumulador.agregar(m);
    if (aceptada) {
      registro.guardarPunto(viaje, m);
      if (++_desdeElUltimoVuelco >= cadaCuantosVuelca) {
        registro.actualizar(
          viaje,
          _acumulador.resultado,
          sinDoppler: estado.value.sinDoppler,
        );
        _desdeElUltimoVuelco = 0;
      }
    }
    estado.value = estado.value.copiar(
      odometria: _acumulador.resultado,
      ultima: _acumulador.ultima,
      // La cruda entra SIEMPRE, sirva o no: es la única forma de ver desde la
      // pantalla que el receptor está hablando aunque el filtro las tire.
      ultimaCruda: m,
      ultimoMotivo: _acumulador.ultimoMotivo,
      limpiarMotivo: aceptada,
    );
  }

  /// Corta la entrega de muestras sin cerrar el viaje. Es lo que hace falta
  /// para una parada larga: se retoma con [arrancar] y el viaje sigue siendo
  /// el mismo.
  Future<void> pausar() async {
    bitacora.anotar(Origen.viaje, 'Viaje en pausa.');
    await _suscripcion?.cancel();
    _suscripcion = null;
    await fuente.detener();
    final viaje = estado.value.viaje;
    if (viaje != null) {
      registro.actualizar(
        viaje,
        _acumulador.resultado,
        sinDoppler: estado.value.sinDoppler,
      );
    }
    estado.value = estado.value.copiar(midiendo: false);
  }

  /// Cierra el viaje: deja el total escrito y suelta el GPS.
  Future<Viaje?> terminar({double? odoTablero}) async {
    final viaje = estado.value.viaje;
    bitacora.anotar(
      Origen.viaje,
      'Terminando el viaje $viaje con ${estado.value.odometria.muestrasUsadas} '
      'muestras usadas y ${estado.value.odometria.muestrasDescartadas} '
      'descartadas.',
    );
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
      sinDoppler: estado.value.sinDoppler,
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
