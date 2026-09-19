import '../../core/bitacora.dart';
import '../respaldo/reporte.dart';
import 'cola.dart';
import 'credencial.dart';
import 'subida.dart';

/// Cómo terminó una tanda de subidas.
class Tanda {
  final int subidos;
  final int fallaron;

  /// El motivo de la primera falla, para poder decirlo sin listar veinte.
  final String? primeraFalla;

  /// `true` si no tiene sentido seguir intentando solo.
  final bool pararDeIntentar;

  const Tanda({
    this.subidos = 0,
    this.fallaron = 0,
    this.primeraFalla,
    this.pararDeIntentar = false,
  });

  bool get huboAlgo => subidos > 0 || fallaron > 0;
}

/// Junta la cola, la credencial y la subida.
///
/// ## La única regla que no se negocia
///
/// **Sube el reporte PARA DESARROLLO y nada más.** Ése es el que no lleva una
/// sola coordenada; el respaldo completo lleva dónde estuvo la camioneta
/// minuto a minuto y **no sale del teléfono por ningún canal**, ni por un
/// chat ni por una nube.
///
/// No es una convención: es el motivo por el que se pudo aceptar que exista
/// una nube. Por eso el alcance no es un parámetro de esta clase — está
/// clavado abajo, y el banco lo comprueba buscando coordenadas en el texto
/// que efectivamente se manda.
class ServicioNube {
  final ColaDeSubida cola;
  final GuardaDeCredencial guarda;
  final Subida subida;

  /// Cómo se arma el reporte de un viaje. Inyectable para el banco.
  final Map<String, dynamic> Function(int viaje) armar;

  ServicioNube({
    required this.cola,
    required this.guarda,
    required this.subida,
    required this.armar,
  });

  bool get configurada => guarda.configurada;

  /// Intenta subir lo que haya pendiente.
  ///
  /// **No lanza y no bloquea nada importante.** Se llama al abrir la
  /// aplicación y cuando alguien toca el botón; si no hay señal, deja todo
  /// como estaba y se reintenta después.
  Future<Tanda> subirPendientes({int tope = 10}) async {
    final c = guarda.credencial;
    if (c == null || !c.completa) {
      return const Tanda(
        pararDeIntentar: true,
        primeraFalla: 'La nube no está configurada.',
      );
    }

    final faltan = cola.pendientes(tope);
    if (faltan.isEmpty) return const Tanda();

    var subidos = 0;
    var fallaron = 0;
    String? primera;

    for (final p in faltan) {
      final r = await subida.subir(
        credencial: c,
        id: _idDe(p.viaje, c),
        reporte: armar(p.viaje),
      );
      if (r.ok) {
        cola.marcarSubido(p.viaje);
        subidos++;
      } else {
        cola.marcarFalla(p.viaje, r.falla ?? 'sin motivo');
        fallaron++;
        primera ??= r.falla;
        // Si el problema es la configuración o la contraseña, insistir con los
        // otros diecinueve sólo gasta batería y llena la cola de la misma
        // falla repetida.
        if (r.esCulpaNuestra) {
          return Tanda(
            subidos: subidos,
            fallaron: fallaron,
            primeraFalla: primera,
            pararDeIntentar: true,
          );
        }
      }
    }

    if (subidos > 0) cola.podar();
    bitacora.anotar(
      Origen.sistema,
      'Subida: $subidos subidos, $fallaron pendientes.',
    );
    return Tanda(subidos: subidos, fallaron: fallaron, primeraFalla: primera);
  }

  /// El identificador del documento. Lleva el usuario adelante para que dos
  /// teléfonos no se pisen el viaje 1, que los dos van a tener.
  static String _idDe(int viaje, Credencial c) {
    final quien = c.mail
        .split('@')
        .first
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    return '$quien-viaje-$viaje';
  }
}

/// El alcance que se sube, y el único que se puede subir.
///
/// **Está acá, suelto y con nombre, para que se vea.** Si algún día alguien
/// quisiera cambiarlo, tiene que venir a esta línea y leer lo de arriba.
const Alcance alcanceQueSeSube = Alcance.paraDesarrollo;
