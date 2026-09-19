import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/fuente.dart';
import 'package:sitd_hilux/features/odometro/integrador.dart';
import 'package:sitd_hilux/features/odometro/muestra.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/odometro/servicio.dart';

/// Un GPS de mentira. Es la razón por la que la fuente es una interfaz: con
/// esto el circuito entero —permiso, viaje, puntos, kilómetros— se prueba sin
/// teléfono, sin emulador y sin salir a manejar.
class FuenteFalsa implements FuenteDeMuestras {
  final _control = StreamController<Lectura>.broadcast(sync: true);
  Disponibilidad respuesta;
  int vecesDetenida = 0;

  FuenteFalsa({this.respuesta = Disponibilidad.listo});

  @override
  Stream<Lectura> get lecturas => _control.stream;

  @override
  Future<Disponibilidad> preparar() async => respuesta;

  @override
  Future<void> detener() async => vecesDetenida++;

  void entregar(Muestra m) => _control.add(Lectura(m));
  void entregarSinDoppler({double? precision}) =>
      _control.add(Lectura(null, precisionCruda: precision));
  void fallar(Object e) => _control.addError(e);
}

Muestra m(int tMs, double v, {double lon = -56.2, double precision = 5}) =>
    Muestra(
      t: tMs,
      lat: -34.9,
      lon: lon,
      velocidad: v,
      precision: precision,
      precisionVel: 0.3,
    );

void main() {
  late Base base;
  late RegistroDeViajes registro;
  late FuenteFalsa fuente;
  late ServicioOdometria servicio;
  var reloj = 100000;

  setUp(() {
    base = Base.abrir(':memory:');
    registro = RegistroDeViajes(base);
    fuente = FuenteFalsa();
    reloj = 100000;
    servicio = ServicioOdometria(
      registro: registro,
      fuente: fuente,
      reloj: () => reloj,
    );
  });

  tearDown(() {
    servicio.cerrarRecursos();
    registro.cerrarRecursos();
    base.cerrar();
  });

  /// Once muestras a 20 m/s, un segundo entre cada una: 200 metros exactos.
  void unViajeDe200Metros() {
    for (var i = 0; i <= 10; i++) {
      fuente.entregar(m(i * 1000, 20, lon: -56.2 + i * 0.0002));
    }
  }

  test('sin permiso no se abre ningun viaje, y queda dicho por que', () async {
    fuente.respuesta = const Disponibilidad(MotivoGps.sinPermiso);
    final ok = await servicio.arrancar();
    expect(ok, isFalse);
    expect(servicio.estado.value.hayViaje, isFalse);
    expect(servicio.estado.value.midiendo, isFalse);
    expect(registro.abierto, isNull);
    expect(servicio.estado.value.problema!.motivo, MotivoGps.sinPermiso);
    expect(servicio.estado.value.problema!.mensaje, contains('permiso'));
  });

  test('con la ubicacion apagada tampoco, y el mensaje dice donde', () async {
    fuente.respuesta = const Disponibilidad(MotivoGps.ubicacionApagada);
    expect(await servicio.arrancar(), isFalse);
    expect(registro.ultimos(), isEmpty);
    expect(servicio.estado.value.problema!.mensaje, contains('ajustes'));
  });

  test('arrancar abre el viaje con la hora del reloj', () async {
    expect(await servicio.arrancar(), isTrue);
    expect(servicio.estado.value.midiendo, isTrue);
    expect(registro.abierto!.inicio, 100000);
    expect(servicio.estado.value.problema, isNull);
  });

  test('cada muestra aceptada se guarda como punto', () async {
    await servicio.arrancar();
    unViajeDe200Metros();
    final viaje = servicio.estado.value.viaje!;
    expect(registro.puntosDe(viaje).length, 11);
    expect(servicio.estado.value.odometria.metros, closeTo(200, 0.001));
    expect(servicio.estado.value.kilometros, closeTo(0.2, 0.000001));
  });

  test('una muestra descartada no llega a la base', () async {
    await servicio.arrancar();
    fuente.entregar(m(1000, 20));
    fuente.entregar(m(2000, 20, precision: 500)); // señal mala
    final viaje = servicio.estado.value.viaje!;
    expect(registro.puntosDe(viaje).length, 1);
    expect(servicio.estado.value.odometria.muestrasDescartadas, 1);
  });

  // Ésta es la trampa del proyecto: una posición sin velocidad Doppler no es
  // una camioneta quieta. Si se contara como muestra buena con velocidad cero,
  // el viaje saldría corto y nada lo diría.
  test('una lectura sin Doppler no se guarda y se cuenta aparte', () async {
    await servicio.arrancar();
    fuente.entregarSinDoppler();
    fuente.entregarSinDoppler();
    final viaje = servicio.estado.value.viaje!;
    expect(registro.puntosDe(viaje), isEmpty);
    expect(servicio.estado.value.sinDoppler, 2);
    expect(servicio.estado.value.odometria.muestrasUsadas, 0);
    expect(servicio.estado.value.odometria.muestrasDescartadas, 0);
  });

  test('la velocidad en pantalla es «todavia no se» y no cero', () async {
    await servicio.arrancar();
    expect(servicio.estado.value.velocidadKmh, isNull);
    fuente.entregar(m(1000, 20));
    expect(servicio.estado.value.velocidadKmh, closeTo(72, 0.001));
  });

  test('terminar cierra el viaje con el total y limpia la pantalla', () async {
    await servicio.arrancar();
    unViajeDe200Metros();
    reloj = 160000;
    final cerrado = await servicio.terminar();
    expect(cerrado!.enMarcha, isFalse);
    expect(cerrado.metros, closeTo(200, 0.001));
    expect(cerrado.fin, 160000);
    expect(servicio.estado.value.hayViaje, isFalse);
    expect(servicio.estado.value.kilometros, 0);
    expect(registro.abierto, isNull);
    expect(fuente.vecesDetenida, 1);
  });

  // El total que quedó escrito tiene que ser el mismo que el que sale de
  // recalcularlo desde los puntos crudos. Si se separan, uno de los dos miente
  // y no hay forma de saber cuál.
  test('lo guardado coincide con recalcular desde los puntos', () async {
    await servicio.arrancar();
    unViajeDe200Metros();
    final cerrado = await servicio.terminar();
    final rehecho = registro.recalcular(cerrado!.id);
    expect(rehecho.metros, closeTo(cerrado.metros, 0.000001));
    expect(rehecho.muestrasUsadas, 11);
  });

  test('pausar no cierra el viaje y seguir no abre otro', () async {
    await servicio.arrancar();
    fuente.entregar(m(1000, 20));
    await servicio.pausar();
    expect(servicio.estado.value.midiendo, isFalse);
    expect(servicio.estado.value.hayViaje, isTrue);
    expect(registro.abierto, isNotNull);

    final viaje = servicio.estado.value.viaje;
    await servicio.arrancar();
    expect(servicio.estado.value.viaje, viaje);
    expect(registro.ultimos().length, 1);
  });

  // La etapa G: cada viaje que termina entra a la cola de subida. Y entra
  // DESPUÉS de cerrarlo, así que si encolar fallara no se pierde un metro.
  group('el viaje terminado avisa, para que lo encolen', () {
    test('avisa con el id del viaje, una sola vez', () async {
      final avisados = <int>[];
      final s = ServicioOdometria(
        registro: registro,
        fuente: fuente,
        reloj: () => reloj,
        alTerminar: avisados.add,
      );
      await s.arrancar();
      final viaje = s.estado.value.viaje!;
      await s.terminar();

      expect(avisados, [viaje]);
      s.cerrarRecursos();
    });

    test('pausar NO avisa: el viaje sigue abierto', () async {
      final avisados = <int>[];
      final s = ServicioOdometria(
        registro: registro,
        fuente: fuente,
        reloj: () => reloj,
        alTerminar: avisados.add,
      );
      await s.arrancar();
      await s.pausar();

      expect(avisados, isEmpty);
      s.cerrarRecursos();
    });

    // Si encolar explota, el viaje ya está cerrado y guardado. Una nube rota
    // no puede costar un viaje.
    test('si el aviso explota, el viaje queda cerrado igual', () async {
      final s = ServicioOdometria(
        registro: registro,
        fuente: fuente,
        reloj: () => reloj,
        alTerminar: (_) => throw StateError('la cola se rompió'),
      );
      await s.arrancar();
      unViajeDe200Metros();
      final viaje = s.estado.value.viaje!;

      final cerrado = await s.terminar();

      expect(cerrado, isNotNull);
      expect(cerrado!.enMarcha, isFalse);
      expect(cerrado.metros, closeTo(200, 0.001));
      expect(registro.porId(viaje)!.enMarcha, isFalse);
      s.cerrarRecursos();
    });
  });

  test('arrancar dos veces seguidas no abre dos viajes', () async {
    await servicio.arrancar();
    await servicio.arrancar();
    expect(registro.ultimos().length, 1);
  });

  // La muerte súbita: MIUI mata la aplicación en medio de un viaje. Al volver
  // a abrir, los puntos están y el total se rehace desde ellos.
  test('un viaje que quedo abierto se retoma con sus kilometros', () async {
    await servicio.arrancar();
    unViajeDe200Metros();
    final viaje = servicio.estado.value.viaje!;

    // Otra sesión de la aplicación, sobre la misma base.
    final otro = ServicioOdometria(
      registro: registro,
      fuente: fuente,
      reloj: () => reloj,
    );
    final retomado = otro.retomarPendiente();
    expect(retomado!.id, viaje);
    expect(otro.estado.value.odometria.metros, closeTo(200, 0.001));
    expect(otro.estado.value.midiendo, isFalse);
    expect(otro.estado.value.ultima!.t, 10000);

    // Y lo que sigue midiendo se suma a eso, no empieza de cero.
    await otro.arrancar();
    fuente.entregar(m(11000, 20, lon: -56.1978));
    expect(otro.estado.value.odometria.metros, closeTo(220, 0.001));
    otro.cerrarRecursos();
  });

  test('sin viaje pendiente no se inventa ninguno', () {
    expect(servicio.retomarPendiente(), isNull);
    expect(servicio.estado.value.hayViaje, isFalse);
  });

  test('si el GPS falla en marcha, se deja de medir y se dice', () async {
    await servicio.arrancar();
    fuente.fallar(StateError('el receptor se apago'));
    expect(servicio.estado.value.midiendo, isFalse);
    expect(servicio.estado.value.problema!.motivo, MotivoGps.falla);
    expect(servicio.estado.value.problema!.detalle, contains('receptor'));
    // El viaje NO se cierra: los kilómetros hechos no se tiran porque el
    // receptor se haya quedado sin cielo.
    expect(registro.abierto, isNotNull);
  });

  group('el estado de la senal', () {
    // Salió de un viaje real de 13 segundos adentro de una casa, que dio
    // 0,0 km y ninguna explicación: «el GPS no ve el cielo» y «la aplicación
    // no anda» se veían igual, porque las dos son un cero.
    test('sin viaje no dice nada', () {
      expect(servicio.estado.value.estadoDeLaSenal, isNull);
    });

    test('midiendo y sin nada todavia, explica la espera', () async {
      await servicio.arrancar();
      expect(
        servicio.estado.value.estadoDeLaSenal,
        contains('Esperando la primera muestra'),
      );
    });

    // El caso real del 2026-09-16: 68 posiciones en dos minutos y medio, ni
    // una con velocidad, y el viaje en cero. «El receptor no entrega nada» y
    // «el receptor entrega y nada sirve» son problemas OPUESTOS y hasta
    // `sitd-13` se decían igual.
    test(
      'con posiciones sin velocidad dice que el receptor SÍ habla',
      () async {
        await servicio.arrancar();
        fuente.entregarSinDoppler();
        fuente.entregarSinDoppler();
        final dicho = servicio.estado.value.estadoDeLaSenal!;
        expect(dicho, contains('Llegaron 2 posiciones'));
        expect(dicho, contains('ninguna trae velocidad'));
      },
    );

    test('con MUCHO error dice que es ubicación de red, no satélite', () async {
      await servicio.arrancar();
      fuente.entregarSinDoppler(precision: 480);
      final dicho = servicio.estado.value.estadoDeLaSenal!;
      expect(dicho, contains('480 m de error'));
      expect(dicho, contains('ubicación de red'));
      // Y dice que eso NO se arregla con paciencia sola.
      expect(dicho, contains('todavía no fijó'));
    });

    test('con poco error es satélite sin resolver la velocidad', () async {
      await servicio.arrancar();
      fuente.entregarSinDoppler(precision: 8);
      final dicho = servicio.estado.value.estadoDeLaSenal!;
      expect(dicho, contains('8 m de error'));
      expect(dicho, isNot(contains('ubicación de red')));
      expect(dicho, contains('El receptor está hablando'));
    });

    test('la precisión de la última sin Doppler queda en el estado', () async {
      await servicio.arrancar();
      fuente.entregarSinDoppler(precision: 300);
      expect(servicio.estado.value.precisionSinDoppler, 300);
      expect(servicio.estado.value.sinDoppler, 1);
    });

    // «Descartadas: 412» no se puede diagnosticar. Estas dos son el mismo
    // contador y dos problemas distintos: uno se arregla saliendo a cielo
    // abierto y el otro dándole permiso de ubicación precisa.
    test('con precision mala dice cuanta, y cuantas van', () async {
      await servicio.arrancar();
      fuente.entregar(m(1000, 20, precision: 80));
      fuente.entregar(m(2000, 20, precision: 80));
      final texto = servicio.estado.value.estadoDeLaSenal!;
      expect(texto, contains('80 m'));
      expect(texto, contains('2 hasta ahora'));
      expect(
        servicio.estado.value.odometria.descartes[MotivoDescarte.precisionMala],
        2,
      );
    });

    test(
      'con precision de cientos de metros, lo llama por su nombre',
      () async {
        await servicio.arrancar();
        fuente.entregar(m(1000, 20, precision: 1500));
        expect(
          servicio.estado.value.estadoDeLaSenal,
          contains('ubicación aproximada'),
        );
      },
    );

    test(
      'una velocidad imposible se cuenta como tal, no como precision',
      () async {
        await servicio.arrancar();
        fuente.entregar(m(1000, 300));
        expect(servicio.estado.value.odometria.descartes, {
          MotivoDescarte.velocidadImplausible: 1,
        });
        expect(servicio.estado.value.estadoDeLaSenal, contains('imposibles'));
      },
    );

    // La cruda entra siempre, sirva o no: es la única forma de ver que el
    // receptor está hablando aunque el filtro tire todo lo que manda.
    test('la ultima CRUDA se guarda aunque se descarte', () async {
      await servicio.arrancar();
      fuente.entregar(m(1000, 20, precision: 900));
      expect(servicio.estado.value.ultima, isNull);
      expect(servicio.estado.value.ultimaCruda!.precision, 900);
      expect(servicio.estado.value.ultimoMotivo, MotivoDescarte.precisionMala);

      fuente.entregar(m(2000, 20));
      expect(servicio.estado.value.ultima, isNotNull);
      expect(servicio.estado.value.ultimoMotivo, isNull);
    });

    test('con la primera muestra buena, se calla', () async {
      await servicio.arrancar();
      fuente.entregarSinDoppler();
      fuente.entregar(m(1000, 20));
      expect(servicio.estado.value.estadoDeLaSenal, isNull);
    });

    test('en pausa tampoco habla: no se esta esperando nada', () async {
      await servicio.arrancar();
      await servicio.pausar();
      expect(servicio.estado.value.estadoDeLaSenal, isNull);
    });
  });

  test('el total se vuelca a la base cada tantos puntos', () async {
    final s = ServicioOdometria(
      registro: registro,
      fuente: fuente,
      reloj: () => reloj,
      cadaCuantosVuelca: 5,
    );
    await s.arrancar();
    final viaje = s.estado.value.viaje!;
    for (var i = 0; i <= 4; i++) {
      fuente.entregar(m(i * 1000, 20, lon: -56.2 + i * 0.0002));
    }
    expect(registro.porId(viaje)!.metros, closeTo(80, 0.001));
    s.cerrarRecursos();
  });
}
