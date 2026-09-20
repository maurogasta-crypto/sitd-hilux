import '../../core/bitacora.dart';
import '../respaldo/reporte.dart';
import 'cola.dart';
import 'credencial.dart';
import 'recorte.dart';
import 'sesion.dart';
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

  /// Dónde vive el `refreshToken`. Opcional para no romper al banco viejo:
  /// sin él, todo funciona como antes y se entra con la contraseña siempre.
  final GuardaDeSesion? sesion;

  /// Cómo se arma el reporte de un viaje. Inyectable para el banco.
  final Map<String, dynamic> Function(int viaje) armar;

  ServicioNube({
    required this.cola,
    required this.guarda,
    required this.subida,
    required this.armar,
    this.sesion,
  });

  bool get configurada => guarda.configurada;

  /// Intenta subir lo que haya pendiente.
  ///
  /// **No lanza y no bloquea nada importante.** Se llama al abrir la
  /// aplicación y cuando alguien toca el botón; si no hay señal, deja todo
  /// como estaba y se reintenta después.
  Future<Tanda> subirPendientes({int tope = 10}) async {
    final c = guarda.credencial;
    // Con una sesión viva la contraseña ya no hace falta: se usó una vez, se
    // guardó el token que devolvió, y se borró. Ver `GuardaDeSesion`.
    final puede =
        c != null &&
        (c.completa || (c.identificaProyecto && (sesion?.hay ?? false)));
    if (!puede) {
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
      // Antes de mandarlo, que entre. Un documento de Firestore no puede
      // pasar de 1 MB, y un reporte rechazado por tamaño lo reintentaría la
      // cola para siempre.
      final listo = recortarParaSubir(armar(p.viaje));
      if (listo.recorte.huboRecorte) {
        bitacora.anotar(
          Origen.sistema,
          'El reporte del viaje ${p.viaje} no entraba '
          '(${listo.recorte.bytesOriginales} bytes) y se recortó: quedaron '
          '${listo.recorte.vibracionesDespues} de '
          '${listo.recorte.vibracionesAntes} ventanas de vibración.',
        );
      }
      if (listo.recorte.noEntro) {
        // Ni pelado entra. Reintentar no lo va a arreglar.
        cola.marcarFalla(p.viaje, 'El reporte no entra ni recortado.');
        fallaron++;
        primera ??= 'El reporte del viaje ${p.viaje} no entra ni recortado.';
        continue;
      }

      final r = await subida.subir(
        credencial: c,
        id: _idDe(p.viaje, c),
        reporte: listo.reporte,
        sesion: sesion,
      );
      if (r.ok) {
        cola.marcarSubido(p.viaje);
        subidos++;
        // La primera subida que sale bien deja el token guardado. A partir de
        // ahí la contraseña no tiene por qué seguir en el teléfono, y se
        // borra: es todo el punto de esta tanda.
        if (sesion != null && sesion!.hay && c.clave.isNotEmpty) {
          guarda.olvidarClave();
        }
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
