import 'package:flutter/foundation.dart';

/// De dónde salió una anotación. Sirve para leer la lista de un vistazo y
/// para filtrarla en el reporte.
enum Origen { permiso, gps, satelites, viaje, sistema }

String nombreDeOrigen(Origen o) => switch (o) {
  Origen.permiso => 'permiso',
  Origen.gps => 'gps',
  Origen.satelites => 'satélites',
  Origen.viaje => 'viaje',
  Origen.sistema => 'sistema',
};

/// Una línea de la bitácora.
@immutable
class Anotacion {
  /// Milisegundos desde la época.
  final int t;
  final Origen origen;
  final String texto;

  const Anotacion({required this.t, required this.origen, required this.texto});

  Map<String, dynamic> aMapa() => {
    't': t,
    'origen': nombreDeOrigen(origen),
    'texto': texto,
  };
}

/// El registro de lo que la aplicación le pidió al sistema y de lo que el
/// sistema contestó.
///
/// **Lo pidió Mauro el 2026-09-16, y con una razón exacta:** la pantalla dice
/// en qué estado está *ahora*, pero no cómo se llegó ahí. «0 posiciones · 6 min
/// en este modo» no distingue un receptor que se suscribió una vez y se quedó
/// callado de uno que se suscribió, falló, se volvió a suscribir y cambió de
/// modo dos veces. Y sobre todo: **cuando alguien está manejando no puede mirar
/// la pantalla**, así que lo que pasa durante un viaje no lo ve nadie. Esto sí.
///
/// **Es un anillo y no una lista que crece**: un viaje largo con el receptor
/// hablando genera miles de eventos, y una lista sin techo en un teléfono de
/// gama de entrada es memoria que no se recupera. Se guardan las últimas
/// [capacidad] y las viejas se caen solas.
///
/// **Y NO entra una coordenada, nunca.** Esta bitácora viaja en el reporte
/// para desarrollo, que es el que se puede mandar por un chat. Dónde estuvo la
/// camioneta no sale del teléfono por acá ni por ningún otro lado: el banco
/// tiene una prueba que busca latitudes y longitudes en el texto entero.
class Bitacora {
  final int capacidad;

  /// El reloj, inyectable: el banco no depende de la hora de la máquina.
  final int Function() ahora;

  /// Sube en cada anotación. La pantalla lo escucha para redibujarse sin
  /// tener que copiar la lista en cada cuadro.
  final ValueNotifier<int> cambios = ValueNotifier(0);

  final List<Anotacion> _anillo = [];

  /// A dónde se copia cada anotación para que sobreviva a cerrar la
  /// aplicación. Se engancha al abrir la base, en `Arranque`.
  ///
  /// **Es opcional a propósito.** La bitácora tiene que funcionar antes de que
  /// la base exista —lo primero que se anota es justamente si la base abrió— y
  /// el banco de pruebas la usa sin ningún SQLite cargado.
  void Function(Anotacion)? alDisco;

  Bitacora({this.capacidad = 300, int Function()? reloj})
    : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Las anotaciones, de la más vieja a la más nueva.
  List<Anotacion> get anotaciones => List.unmodifiable(_anillo);

  /// De la más nueva a la más vieja, que es como se lee en pantalla.
  List<Anotacion> get alReves => _anillo.reversed.toList();

  int get cuantas => _anillo.length;

  void anotar(Origen origen, String texto) {
    final a = Anotacion(t: ahora(), origen: origen, texto: texto);
    _anillo.add(a);
    if (_anillo.length > capacidad) {
      _anillo.removeRange(0, _anillo.length - capacidad);
    }
    // Que falle el disco no puede hacer caer lo que se estaba diagnosticando:
    // esto anota, no mide.
    try {
      alDisco?.call(a);
    } catch (_) {}
    cambios.value++;
  }

  /// Igual que [anotar] pero descarta la repetida seguida.
  ///
  /// **Existe porque el GPS entrega una vez por segundo.** Sin esto, un viaje
  /// de una hora deja tres mil seiscientas líneas idénticas y la bitácora se
  /// vuelve ilegible justo cuando hace falta. Lo que importa de una entrega es
  /// la primera y el cambio de estado, no el latido.
  void anotarSiCambio(Origen origen, String texto) {
    if (_anillo.isNotEmpty &&
        _anillo.last.origen == origen &&
        _anillo.last.texto == texto) {
      return;
    }
    anotar(origen, texto);
  }

  void limpiar() {
    _anillo.clear();
    cambios.value++;
  }

  List<Map<String, dynamic>> aMapa() => [for (final a in _anillo) a.aMapa()];
}

/// La bitácora de esta corrida de la aplicación.
///
/// Es global a propósito y es la única cosa global del proyecto: la escriben
/// piezas que no se conocen entre sí —la cascada, la fuente del GPS, el
/// servicio del viaje, el canal de satélites— y pasarla por parámetro a través
/// de las cuatro sería ruido en cada firma para un registro de diagnóstico. No
/// guarda estado del que dependa nada: si se pierde, no se pierde un metro.
final bitacora = Bitacora();
