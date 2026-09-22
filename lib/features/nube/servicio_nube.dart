import '../../core/bitacora.dart';
import '../../core/version.dart';
import '../odometro/registro.dart';
import '../respaldo/reporte.dart';
import 'cola.dart';
import 'credencial.dart';
import 'recorrido.dart';
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

  /// Los viajes y sus puntos, para poder subir el RECORRIDO.
  ///
  /// Opcional a propósito: sin esto todo lo demás anda exactamente igual y el
  /// recorrido simplemente no se sube. Es la misma forma en que entró
  /// `sesion` — una capacidad nueva no puede romper a la anterior.
  final RegistroDeViajes? viajes;

  ServicioNube({
    required this.cola,
    required this.guarda,
    required this.subida,
    required this.armar,
    this.sesion,
    this.viajes,
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
        id: _idDe(p.viaje, c, inicio: _inicioDe(listo.reporte)),
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

  /// Sube a la nube el recorrido de los viajes que todavía no están.
  ///
  /// ## Por qué NO va en la cola automática, y es una decisión
  ///
  /// El reporte sin coordenadas sube solo al terminar cada viaje, y así se
  /// queda. El recorrido sube **cuando Mauro toca el botón**.
  ///
  /// No es desconfianza del código: es que subir el recorrido es la única
  /// parte de este proyecto que saca de la camioneta un dato que no se puede
  /// volver a guardar. Un acto deliberado es la contención que le queda a esa
  /// mitad una vez que se decidió que puede salir, y no cuesta nada —el botón
  /// está al lado del respaldo—. Si algún día molesta, esto se llama desde
  /// `subirPendientes` y listo; que hoy no se llame de ahí es el punto.
  ///
  /// **Primero pregunta qué hay arriba.** Sin eso, cada vez que alguien
  /// tocara el botón se reintentarían todos los viajes de la historia: el
  /// servidor los rebotaría con 409 y no se rompería nada, pero serían cien
  /// kilobytes por viaje subidos al pedo, con los datos del teléfono.
  Future<TandaDeRecorridos> subirRecorridos({int tope = 20}) async {
    final registro = viajes;
    if (registro == null) {
      return const TandaDeRecorridos(
        falla: 'Esta compilación no puede subir recorridos.',
      );
    }
    final c = guarda.credencial;
    final puede =
        c != null &&
        (c.completa || (c.identificaProyecto && (sesion?.hay ?? false)));
    if (!puede) {
      return const TandaDeRecorridos(falla: 'La nube no está configurada.');
    }

    final arriba = {
      for (final r in await subida.listarRecorridos(
        credencial: c,
        sesion: sesion,
      ))
        r.id,
    };

    var subidos = 0;
    var yaEstaban = 0;
    var fallaron = 0;
    String? primera;

    for (final v in registro.ultimos(tope)) {
      final id = idDeRecorrido(v.inicio, c);
      if (arriba.contains(id)) {
        yaEstaban++;
        continue;
      }
      final puntos = registro.puntosDe(v.id);
      if (puntos.isEmpty) continue;

      final r = await subida.subirRecorrido(
        credencial: c,
        id: id,
        recorrido: codificarRecorrido(puntos),
        viaje: fichaDelViaje(v),
        inicio: v.inicio,
        puntos: puntos.length,
        sello: selloApp,
        sesion: sesion,
      );
      if (r.ok) {
        subidos++;
      } else {
        fallaron++;
        primera ??= r.falla;
        if (r.esCulpaNuestra) break;
      }
    }

    bitacora.anotar(
      Origen.sistema,
      'Recorridos: $subidos subidos, $yaEstaban ya estaban, $fallaron fallaron.',
    );
    return TandaDeRecorridos(
      subidos: subidos,
      yaEstaban: yaEstaban,
      fallaron: fallaron,
      falla: primera,
    );
  }

  /// La ficha de un viaje, que viaja al lado de su recorrido.
  ///
  /// Son los mismos nombres que usa el reporte para desarrollo, a propósito:
  /// dos vocabularios para el mismo viaje es el error de `perm`/`permiso` que
  /// este ecosistema ya pagó una vez.
  static Map<String, dynamic> fichaDelViaje(Viaje v) => {
    'inicio': v.inicio,
    'fin': v.fin,
    'metros': v.metros,
    'metrosHaversine': v.metrosHaversine,
    'cortes': v.cortes,
    'descartadas': v.descartadas,
    'sinDoppler': v.sinDoppler,
    'precisionDescartada': v.precisionDescartada,
    'motivos': v.motivos,
    'odoTableroIni': v.odoTableroIni,
    'odoTableroFin': v.odoTableroFin,
    'notas': v.notas,
  };

  /// El identificador del documento. Lleva el usuario adelante para que dos
  /// teléfonos no se pisen el viaje 1, que los dos van a tener.
  ///
  /// ## Y la segunda mitad es el INSTANTE, no el número del viaje
  ///
  /// **Esto estuvo mal hasta el 2026-09-21 y lo rompí yo con `sitd-25`.** El
  /// número que un viaje tiene en el teléfono no es estable: al sumar o
  /// reemplazar un respaldo los viajes se renumeran. Con el número adentro
  /// del identificador, un viaje nuevo podía caer sobre el documento de
  /// OTRO — la escritura rebota con un 409, la cola lo lee como «ya estaba»,
  /// el viaje sale de la cola y **nunca se sube, sin que nada avise**. Es
  /// exactamente la forma de fallar que este proyecto ya pagó tres veces: algo
  /// que parece hecho y no lo está.
  ///
  /// El instante en que arrancó no se renumera nunca, y es además la misma
  /// llave con la que `importar.dart` reconoce un viaje repetido. Un solo
  /// concepto de «cuál viaje es éste» en todo el proyecto.
  ///
  /// Los documentos subidos con el esquema viejo quedan donde están y siguen
  /// siendo válidos: la cola ya los tiene marcados como subidos, así que no se
  /// duplican. Lo nuevo entra con el identificador nuevo.
  static String _idDe(int viaje, Credencial c, {int? inicio}) {
    final quien = _quien(c);
    return inicio != null ? '$quien-t$inicio' : '$quien-viaje-$viaje';
  }

  /// El identificador del recorrido del mismo viaje. Comparte la llave con el
  /// reporte a propósito: en la consola, los dos documentos de un viaje se
  /// ven uno al lado del otro.
  static String idDeRecorrido(int inicio, Credencial c) =>
      '${_quien(c)}-t$inicio';

  static String _quien(Credencial c) =>
      c.mail.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');

  /// El instante en que arrancó el viaje que trae este reporte, o `null` si
  /// el reporte no lo dice.
  static int? _inicioDe(Map<String, dynamic> reporte) {
    final vs = reporte['viajes'];
    if (vs is! List || vs.isEmpty) return null;
    final v = vs.first;
    final i = v is Map ? v['inicio'] : null;
    return i is int ? i : null;
  }
}

/// El alcance que se sube, y el único que se puede subir.
///
/// **Está acá, suelto y con nombre, para que se vea.** Si algún día alguien
/// quisiera cambiarlo, tiene que venir a esta línea y leer lo de arriba.
const Alcance alcanceQueSeSube = Alcance.paraDesarrollo;

/// Cómo salió una tanda de recorridos.
class TandaDeRecorridos {
  final int subidos;

  /// Los que ya estaban arriba. **No son una falla y se cuentan aparte**: la
  /// pantalla que dice «0 subidos» sin esto parece rota, y lo que pasó es que
  /// no había nada que subir.
  final int yaEstaban;
  final int fallaron;

  /// La primera falla, en palabras. `null` si no hubo.
  final String? falla;

  const TandaDeRecorridos({
    this.subidos = 0,
    this.yaEstaban = 0,
    this.fallaron = 0,
    this.falla,
  });

  String get resumen {
    if (falla != null && subidos == 0) return falla!;
    final partes = <String>[];
    if (subidos > 0) {
      partes.add('$subidos ${subidos == 1 ? 'recorrido' : 'recorridos'}');
    }
    if (yaEstaban > 0) partes.add('$yaEstaban ya estaban');
    if (fallaron > 0) partes.add('$fallaron no pudieron');
    return partes.isEmpty
        ? 'No había ningún viaje con recorrido para subir.'
        : 'Subida del recorrido: ${partes.join(', ')}.';
  }
}
