import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/bitacora.dart';
import '../permisos/avisos.dart';
import 'fuente.dart';
import 'fuente_gps.dart';

/// Un escalón de la cascada: cómo pedir y cuánto esperar antes de bajar al
/// siguiente.
@immutable
class Escalon {
  final ModoGps modo;

  /// Cuánto se le da a este modo para entregar la PRIMERA lectura.
  ///
  /// Sólo cuenta hasta la primera: una vez que el receptor habló, la cascada
  /// se queda donde está y no vuelve a moverse. Un silencio posterior es otro
  /// problema —un stream que se muere a mitad de viaje— y bajar de escalón no
  /// lo arreglaría, sólo cambiaría un modo que ya se sabe que funciona.
  final Duration paciencia;

  const Escalon(this.modo, this.paciencia);
}

/// Los tres escalones, en el orden en que se prueban.
///
/// El primero es el que se quiere: es el único que sigue midiendo con la
/// pantalla apagada. Los otros dos son menos que eso, y por eso están abajo —
/// pero medir de menos es infinitamente más que no medir.
///
/// Al primero se le da un minuto y medio porque un receptor frío tarda entre
/// treinta segundos y un minuto en fijar satélites: bajarlo antes sería
/// abandonar el modo bueno por impaciencia.
const List<Escalon> escalonesPorDefecto = [
  Escalon(ModoGps.normal, Duration(seconds: 90)),
  Escalon(ModoGps.sinNotificacion, Duration(seconds: 45)),
  Escalon(ModoGps.receptorDirecto, Duration(seconds: 45)),
];

/// Prueba las tres formas de pedirle posiciones a Android, una tras otra,
/// hasta que alguna entregue.
///
/// **Existe por dos salidas a cielo abierto que terminaron en cero lecturas.**
/// Cero —ni siquiera descartadas— quiere decir que el problema está antes de
/// todo lo que este proyecto controla: el stream se abrió, no dio un solo
/// error, y no llegó nada. Un `Stream` callado no se distingue de un receptor
/// que todavía no fijó satélites, y esperar a que alguien mire la pantalla
/// para cambiar de modo a mano es pedirle a quien está manejando que depure.
///
/// La regla es una sola: **si un modo no entregó nada en su plazo, se pasa al
/// siguiente y se dice cuál quedó puesto.** El modo activo se muestra en la
/// pantalla del viaje, así que cuando el viaje termina se sabe cuál funcionó —
/// que es exactamente el dato que hoy falta para arreglar la causa.
class FuenteEnCascada implements FuenteDeMuestras {
  final List<Escalon> escalones;

  /// Cómo se construye la fuente de cada modo. Inyectable para que el banco
  /// ejercite la cascada entera sin GPS y sin teléfono.
  final FuenteDeMuestras Function(ModoGps) construir;

  /// El modo que está puesto ahora mismo. La pantalla lo escucha.
  final ValueNotifier<ModoGps> modo;

  /// `true` desde que llegó la primera lectura. A partir de ahí la cascada se
  /// queda quieta.
  bool get entrego => _entrego;

  /// Los modos que se probaron, en orden, incluido el actual.
  List<ModoGps> get probados =>
      escalones.take(_indice + 1).map((e) => e.modo).toList();

  /// Cómo se pide el permiso de notificaciones. Inyectable para el banco.
  final PedirAviso pedirAviso;

  /// En qué quedó ese permiso la última vez que se pidió, o `null` si todavía
  /// no se pidió. La pantalla del viaje lo muestra cuando no es «concedido»:
  /// sin cartel, el servicio en primer plano es invisible y un Xiaomi lo mata
  /// sin que nadie se entere.
  final ValueNotifier<EstadoAviso?> aviso = ValueNotifier(null);

  FuenteEnCascada({
    FuenteDeMuestras Function(ModoGps)? construir,
    PedirAviso? pedirAviso,
    this.escalones = escalonesPorDefecto,
  }) : construir = construir ?? ((m) => FuenteGps(modo: m)),
       pedirAviso = pedirAviso ?? pedirAvisoDelSistema,
       modo = ValueNotifier(escalones.first.modo);

  int _indice = 0;
  bool _entrego = false;
  FuenteDeMuestras? _actual;
  StreamSubscription<Lectura>? _suscripcion;
  Timer? _reloj;
  StreamController<Lectura>? _control;

  @override
  Stream<Lectura> get lecturas {
    final c = _control ??= StreamController<Lectura>(
      onListen: _engancharse,
      onCancel: _soltar,
    );
    return c.stream;
  }

  void _engancharse() {
    final escalon = escalones[_indice];
    modo.value = escalon.modo;
    bitacora.anotar(
      Origen.gps,
      'Pidiendo posiciones en modo ${nombreDeModo(escalon.modo)}. Si no llega '
      'ninguna en ${escalon.paciencia.inSeconds} s, se baja de escalón.',
    );
    final fuente = construir(escalon.modo);
    _actual = fuente;
    _suscripcion = fuente.lecturas.listen(
      _recibir,
      onError: _falla,
      // Que el receptor cierre el stream sin decir nada es otra forma del
      // mismo silencio, y se trata igual.
      onDone: _seCerro,
    );
    _reloj = Timer(escalon.paciencia, _bajarSiSePuede);
  }

  void _recibir(Lectura l) {
    if (!_entrego) {
      bitacora.anotar(
        Origen.gps,
        'PRIMERA entrega del receptor, en modo ${nombreDeModo(modo.value)}'
        '${l.sinDoppler ? " (sin velocidad Doppler, pero el receptor habló)" : ""}. '
        'La cascada se queda acá.',
      );
    }
    _entrego = true;
    _reloj?.cancel();
    _reloj = null;
    _control?.add(l);
  }

  void _falla(Object e) {
    bitacora.anotar(
      Origen.gps,
      'El modo ${nombreDeModo(modo.value)} falló: $e',
    );
    if (_hayMas) {
      _bajarSiSePuede();
      return;
    }
    // En el último escalón no hay a dónde ir: el error es la respuesta y sube
    // tal cual, que es lo que la pantalla necesita para decir la causa.
    _control?.addError(e);
  }

  bool get _hayMas => !_entrego && _indice + 1 < escalones.length;

  /// El escalón cerró el stream por su cuenta. Si hay a dónde bajar se baja;
  /// si no, se cierra la salida, porque quedarse escuchando un stream muerto
  /// deja la pantalla en «Esperando» para siempre.
  void _seCerro() {
    if (_hayMas) {
      _bajarSiSePuede();
      return;
    }
    unawaited(_control?.close() ?? Future.value());
  }

  void _bajarSiSePuede() {
    if (!_hayMas) return;
    _indice++;
    unawaited(_cambiar());
  }

  Future<void> _cambiar() async {
    final vieja = _actual;
    final sub = _suscripcion;
    final reloj = _reloj;
    _actual = null;
    _suscripcion = null;
    _reloj = null;
    reloj?.cancel();
    await sub?.cancel();
    await vieja?.detener();
    // Cancelar mientras se bajaba de escalón: no se abre el siguiente.
    final c = _control;
    if (c == null || c.isClosed) return;
    _engancharse();
  }

  /// Pide el permiso una sola vez, con el primer modo. El permiso de
  /// ubicación no depende de cómo se pidan las posiciones, así que preguntarlo
  /// en cada escalón sería abrir el mismo diálogo tres veces.
  @override
  Future<Disponibilidad> preparar() async {
    // El permiso de notificaciones se pide ACÁ y no en cada escalón: es de la
    // aplicación, no del modo, y abrir el mismo diálogo tres veces sería
    // castigar a quien está por salir a manejar. Que salga negado no impide
    // medir —por eso no se mira el resultado para decidir—, pero queda a la
    // vista, que es lo que hoy falta.
    aviso.value = await pedirAviso();
    bitacora.anotar(
      Origen.permiso,
      'Permiso de notificaciones: ${textoDeAviso(aviso.value!)}.',
    );
    // El permiso de ubicación tampoco depende del modo.
    return (_actual ?? construir(escalones[_indice].modo)).preparar();
  }

  @override
  Future<void> detener() => _soltar();

  /// Suelta el escalón puesto y deja la cascada como recién creada.
  ///
  /// **No cierra el controlador**: esto corre como `onCancel`, o sea con la
  /// suscripción ya cancelada, y cerrar ahí adentro es pedirle al controlador
  /// que se espere a sí mismo. Se suelta la referencia y el próximo `listen`
  /// arma uno nuevo, que es lo que hace falta para que un segundo viaje
  /// arranque otra vez por el modo bueno.
  Future<void> _soltar() async {
    final vieja = _actual;
    final sub = _suscripcion;
    _reloj?.cancel();
    _reloj = null;
    _actual = null;
    _suscripcion = null;
    _control = null;
    _indice = 0;
    _entrego = false;
    modo.value = escalones.first.modo;
    await sub?.cancel();
    await vieja?.detener();
  }
}
