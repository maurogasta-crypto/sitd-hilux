import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/bitacora.dart';
import '../permisos/avisos.dart';
import '../sensores/satelites.dart';
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
/// Los escalones reordenados para que [primero] quede adelante.
///
/// **No se saca ninguno**: si el recordado deja de andar, la cascada sigue
/// teniendo a dónde bajar. Lo único que cambia es por cuál empieza.
///
/// Vive acá desde el 2026-09-21 y antes estaba en `modo_recordado.dart`. Se
/// mudó porque la cascada tiene que poder reordenarse SOLA al empezar cada
/// viaje, y ese archivo ya importa a éste: dejarla allá era un import
/// circular. `modo_recordado.dart` la sigue exportando, así que nada de lo que
/// ya la usaba cambió.
List<Escalon> escalonesEmpezandoPor(ModoGps? primero, List<Escalon> todos) {
  if (primero == null) return todos;
  final i = todos.indexWhere((e) => e.modo == primero);
  if (i <= 0) return todos;
  return [todos[i], ...todos.where((e) => e.modo != primero)];
}

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
      _orden.take(_indice + 1).map((e) => e.modo).toList();

  /// Cómo se pide el permiso de notificaciones. Inyectable para el banco.
  final PedirAviso pedirAviso;

  /// La escucha del motor GNSS, para reintentar el enganche una vez que el
  /// permiso de ubicación quedó dado — que es lo único que le faltaba.
  final Satelites? satelites;

  /// Dónde se anota el modo que entregó, para que el próximo viaje arranque
  /// por ahí en vez de volver a esperar noventa segundos. Ver
  /// `modo_recordado.dart`.
  final void Function(ModoGps)? alEntregar;

  /// Con qué modo conviene empezar, PREGUNTADO al empezar cada viaje.
  ///
  /// **Es una función y no un valor, y ésa es toda la corrección del
  /// 2026-09-21.** Antes el orden de los escalones se calculaba UNA vez, al
  /// abrir la aplicación (`arranque.dart` llamaba a `escalonesEmpezandoPor` y
  /// le pasaba el resultado ya hecho). Entonces lo que la cascada aprendía a
  /// mitad de sesión no se usaba hasta reiniciar.
  ///
  /// Se vio en el primer viaje real, el 2026-09-20: la bitácora anotó «el modo
  /// Sin notificación entregó, el próximo viaje arranca por ahí» y al reanudar
  /// el viaje volvió a empezar por «Normal» y pagó los noventa segundos otra
  /// vez. Preguntando cada vez, eso no vuelve a pasar.
  final ModoGps? Function()? modoPreferido;

  /// El orden con el que se está trabajando ahora. Sale de [escalones] pasado
  /// por [modoPreferido], y se recalcula al soltar — o sea entre un viaje y el
  /// siguiente.
  late List<Escalon> _orden = escalonesEmpezandoPor(
    modoPreferido?.call(),
    escalones,
  );

  /// En qué quedó ese permiso la última vez que se pidió, o `null` si todavía
  /// no se pidió. La pantalla del viaje lo muestra cuando no es «concedido»:
  /// sin cartel, el servicio en primer plano es invisible y un Xiaomi lo mata
  /// sin que nadie se entere.
  final ValueNotifier<EstadoAviso?> aviso = ValueNotifier(null);

  FuenteEnCascada({
    FuenteDeMuestras Function(ModoGps)? construir,
    PedirAviso? pedirAviso,
    this.satelites,
    this.alEntregar,
    this.modoPreferido,
    this.escalones = escalonesPorDefecto,
  }) : construir = construir ?? ((m) => FuenteGps(modo: m)),
       pedirAviso = pedirAviso ?? pedirAvisoDelSistema,
       modo = ValueNotifier(
         escalonesEmpezandoPor(
           modoPreferido?.call(),
           escalones,
         ).first.modo,
       );

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
    final escalon = _orden[_indice];
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
      alEntregar?.call(modo.value);
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

  bool get _hayMas => !_entrego && _indice + 1 < _orden.length;

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
    final d = await (_actual ?? construir(_orden[_indice].modo)).preparar();
    // Y recién ACÁ, con el permiso ya resuelto, tiene sentido volver a pedirle
    // al sistema la cuenta de satélites: sin permiso de ubicación fina la
    // rechaza, y en `sitd-13` se pedía al abrir la aplicación y nunca más.
    if (d.puedeArrancar) await satelites?.reintentarSiHaceFalta();
    return d;
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
    // Se vuelve a preguntar ACÁ, que es entre un viaje y el siguiente: si
    // durante el que terminó se aprendió cuál modo entrega, el próximo empieza
    // por ése en vez de volver a esperar los noventa segundos del primero.
    _orden = escalonesEmpezandoPor(modoPreferido?.call(), escalones);
    modo.value = _orden.first.modo;
    await sub?.cancel();
    await vieja?.detener();
  }
}
