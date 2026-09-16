import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sitd_hilux/core/db/base.dart';
import 'package:sitd_hilux/features/odometro/registro.dart';
import 'package:sitd_hilux/features/vibracion/fuente_vibracion.dart';
import 'package:sitd_hilux/features/vibracion/registro_vibracion.dart';
import 'package:sitd_hilux/features/vibracion/servicio_vibracion.dart';

class AcelerometroFalso implements FuenteDeVibracion {
  final _control = StreamController<Sacudon>.broadcast(sync: true);
  int vecesDetenido = 0;

  @override
  Stream<Sacudon> get sacudones => _control.stream;

  @override
  Future<void> detener() async => vecesDetenido++;

  /// Sacude durante [segundos] a [hz], con una vibración de [f] Hz encima de
  /// la gravedad, empezando en [desde] milisegundos.
  void sacudir({
    required int desde,
    required double segundos,
    double hz = 50,
    double f = 8.6,
  }) {
    final n = (hz * segundos).round();
    for (var i = 0; i < n; i++) {
      _control.add(
        Sacudon(
          desde + (i * 1000 / hz).round(),
          9.8 + 0.3 * math.sin(2 * math.pi * f * i / hz),
        ),
      );
    }
  }

  void fallar(Object e) => _control.addError(e);
}

void main() {
  late Base base;
  late RegistroDeVibracion registro;
  late RegistroDeViajes viajes;
  late AcelerometroFalso fuente;
  late ServicioVibracion servicio;
  double? velocidad;

  setUp(() {
    base = Base.abrir(':memory:');
    registro = RegistroDeVibracion(base);
    viajes = RegistroDeViajes(base);
    fuente = AcelerometroFalso();
    velocidad = 65;
    servicio = ServicioVibracion(
      registro: registro,
      fuente: fuente,
      velocidadKmh: () => velocidad,
      reloj: () => 0,
    );
  });

  tearDown(() {
    viajes.cerrarRecursos();
    base.cerrar();
  });

  int unViaje() => viajes.abrir(inicio: 0);

  test('arranca, junta y guarda una ventana por cada cinco segundos', () {
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.sacudir(desde: 0, segundos: 16);
    expect(servicio.guardadas, 3);
    expect(registro.deViaje(viaje).length, 3);
  });

  test('la ventana queda con la cubeta de la velocidad de ese momento', () {
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.sacudir(desde: 0, segundos: 6);
    expect(registro.deViaje(viaje).single.cubeta, 4); // 65 km/h
  });

  test(
    'yendo despacio no se guarda nada: eso es el camino, no la mecanica',
    () {
      velocidad = 12;
      final viaje = unViaje();
      servicio.arrancar(viaje);
      fuente.sacudir(desde: 0, segundos: 12);
      expect(registro.deViaje(viaje), isEmpty);
      expect(servicio.descartadas, greaterThan(0));
    },
  );

  test('sin velocidad todavia tampoco: un espectro sin cubeta no sirve', () {
    velocidad = null;
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.sacudir(desde: 0, segundos: 12);
    expect(registro.deViaje(viaje), isEmpty);
  });

  // Una ventana que empieza a 58 y termina a 72 km/h mezcla dos espectros
  // distintos, y mezclados no se parecen a ninguno de los dos.
  test('si la velocidad cambia de cubeta en el medio, se descarta', () {
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.sacudir(desde: 0, segundos: 3);
    velocidad = 95; // cubeta 7
    fuente.sacudir(desde: 3000, segundos: 3);
    expect(registro.deViaje(viaje), isEmpty);
    expect(servicio.descartadas, 1);
  });

  test(
    'la ventana guardada trae la frecuencia medida y el espectro entero',
    () {
      final viaje = unViaje();
      servicio.arrancar(viaje);
      fuente.sacudir(desde: 0, segundos: 6, hz: 45);
      final v = registro.deViaje(viaje).single;
      expect(v.hz, closeTo(45, 1));
      expect(v.completa, isTrue);
      expect(v.bandas.indexOf(v.bandas.reduce(math.max)), 4); // 8,6 Hz
      expect(v.rms, greaterThan(0));
    },
  );

  test('detener corta y suelta el sensor', () async {
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.sacudir(desde: 0, segundos: 6);
    await servicio.detener();
    expect(servicio.midiendo, isFalse);
    expect(fuente.vecesDetenido, 1);
    fuente.sacudir(desde: 20000, segundos: 6);
    expect(registro.deViaje(viaje).length, 1); // no entró ninguna más
  });

  // La odometría es lo que no se puede perder: un acelerómetro que falla no
  // puede llevarse el viaje puesto.
  test('si el sensor falla, se deja de juntar y nada mas', () {
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.fallar(StateError('el sensor se fue'));
    expect(servicio.midiendo, isFalse);
    expect(viajes.abierto, isNotNull);
  });

  test(
    'las ventanas vuelven agrupadas por viaje, como las pide el analisis',
    () {
      final a = unViaje();
      servicio.arrancar(a);
      fuente.sacudir(desde: 0, segundos: 11);
      servicio.detener();

      final b = unViaje();
      servicio.arrancar(b);
      fuente.sacudir(desde: 60000, segundos: 6);

      final porViaje = registro.porViaje();
      expect(porViaje[a]!.length, 2);
      expect(porViaje[b]!.length, 1);
      expect(registro.ultimosViajes(), [b, a]); // el más nuevo primero
      expect(registro.ventanasPorCubeta()[4], 3);
    },
  );

  test('borrar el viaje se lleva sus vibraciones', () {
    final viaje = unViaje();
    servicio.arrancar(viaje);
    fuente.sacudir(desde: 0, segundos: 6);
    base.db.execute('DELETE FROM viajes WHERE id = ?', [viaje]);
    expect(registro.deViaje(viaje), isEmpty);
  });
}
