import 'dart:io';

import '../../core/aparato.dart';
import '../../core/bitacora.dart';
import '../../core/db/base.dart';
import '../../core/db/esquema.dart';
import '../../core/version.dart';
import '../calibracion/calibracion.dart';
import '../odometro/registro.dart';
import '../respaldo/importar.dart';
import '../respaldo/reporte.dart';
import '../respaldo/saneado.dart';
import 'cola.dart';
import 'credencial.dart';
import 'recorrido.dart';
import 'recorte.dart';
import 'respaldo_nube.dart';
import 'sesion.dart';
import 'subida.dart';

/// Cómo terminó «Sincronizar» (`sitd-47`), paso por paso.
class Sincronizado {
  /// Lo pendiente de la cola y las calibraciones.
  final Tanda pendientes;

  /// El respaldo de la nube con el que se comparó (`null`: no había).
  final RespaldoEnLaNube? comparado;

  /// Lo que se trajo de la nube y se sumó (`null`: no se bajó nada).
  final Sumado? traido;

  /// La copia nueva que subió (`null`: no hizo falta, o falló).
  final RespaldoEnLaNube? subido;

  /// Por qué no se subió la copia, si no hacía falta.
  final bool alDia;

  /// Lo que salió mal, en una frase. Lo anterior a la falla quedó hecho.
  final String? falla;

  /// Copias viejas de la nube que se borraron (`sitd-50`).
  final int borrados;

  const Sincronizado({
    required this.pendientes,
    this.comparado,
    this.traido,
    this.subido,
    this.alDia = false,
    this.falla,
    this.borrados = 0,
  });
}

/// Lo que se le dice a quien tocó Sincronizar: qué subió, qué trajo y si
/// quedó al día. Aparte para que el banco lo pruebe.
String textoDeSincronizado(Sincronizado r) {
  final partes = <String>[];
  final p = r.pendientes;
  if (p.subidos > 0) {
    partes.add(
      'Subió ${p.subidos} ${p.subidos == 1 ? 'pendiente' : 'pendientes'}.',
    );
  }
  final tr = r.traido;
  if (tr != null && tr.salioBien && !tr.nadaNuevo) {
    partes.add('Trajo de la nube: ${tr.resumen}');
  }
  if (r.subido != null) {
    partes.add('Dejó en la nube una copia completa (${r.subido!.resumen}).');
  } else if (r.alDia) {
    partes.add(
      tr == null || tr.nadaNuevo
          ? 'Ya estaba todo sincronizado.'
          : 'La nube ya tenía todo lo de este teléfono.',
    );
  }
  if (r.falla != null) partes.add(r.falla!);
  if (p.fallaron > 0) {
    partes.add(
      '${p.fallaron} ${p.fallaron == 1 ? 'pendiente quedó' : 'pendientes quedaron'} esperando'
      '${p.primeraFalla != null ? ': ${p.primeraFalla}' : '.'}',
    );
  }
  if (r.borrados > 0) {
    partes.add(
      'Borró ${r.borrados} ${r.borrados == 1 ? 'copia vieja' : 'copias viejas'} de la nube.',
    );
  }
  if (tr != null && tr.viajes > 0) {
    partes.add('Volvé a la pantalla principal para ver los viajes nuevos.');
  }
  return partes.isEmpty ? 'Listo.' : partes.join('\n');
}

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
/// ## La regla de `reportes/`, que sigue intacta
///
/// **A `reportes/` sube el reporte PARA DESARROLLO y nada más**, que es el que
/// no lleva una sola coordenada. El alcance no es un parámetro de esta clase:
/// está clavado abajo, en `alcanceQueSeSube`, y el banco lo comprueba buscando
/// latitudes y longitudes en el texto que efectivamente se manda.
///
/// ## Y lo que cambió el 2026-09-21, que hay que leer junto
///
/// Hasta esa fecha este comentario decía que el recorrido **no sale del
/// teléfono por ningún canal, ni por un chat ni por una nube**, y que ésa era
/// la razón por la que se pudo aceptar que existiera una nube. Mauro la dio
/// vuelta a propósito —«por más que haya puntos o coordenadas»— para poder
/// cruzar todos los datos desde el chat en esta etapa.
///
/// El recorrido sube por [subirRecorridos], **a `recorridos/` y no acá**, y
/// **sólo cuando alguien toca el botón**. Que sean dos colecciones es la
/// contención: así la propiedad de `reportes/` —y la prueba que la cuida—
/// sigue siendo cierta, y si algo sale mal sale mal en un solo lugar.
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

  /// Las calibraciones del garage (`sitd-46`). Opcional como `viajes`: sin
  /// esto no suben y todo lo demás sigue igual.
  final RegistroDeCalibraciones? calibraciones;

  ServicioNube({
    required this.cola,
    required this.guarda,
    required this.subida,
    required this.armar,
    this.sesion,
    this.viajes,
    this.calibraciones,
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

    // sitd-46: primero las calibraciones terminadas que no subieron. Antes
    // viajaban sólo adentro del reporte de un viaje, así que una medida
    // hecha en el garage no llegaba hasta el próximo viaje.
    final cal = await _subirCalibraciones(c);
    var subidos = cal.subidas;
    var fallaron = cal.fallaron;
    String? primera = cal.falla;

    final faltan = cola.pendientes(tope);
    if (faltan.isEmpty) {
      return Tanda(subidos: subidos, fallaron: fallaron, primeraFalla: primera);
    }

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

  /// Sube la base ENTERA, saneada, a `respaldos/` (`sitd-34`).
  ///
  /// Es lo que deja levantar todo en otro teléfono: viajes, puntos, cargas,
  /// vibraciones, bitácora y pruebas de soporte. Sale por el mismo
  /// [hacerCopiaSaneada] que el botón de compartir, así que la credencial de
  /// la nube **no sube**: se saca de la copia y se comprueban los bytes antes
  /// de mandar nada.
  ///
  /// **No va en la cola de cada viaje**: esto lleva el recorrido de todos
  /// los viajes a la vez. Lo sube [sincronizar], que desde `sitd-50` corre
  /// sola al abrir y al cerrar un viaje (Mauro lo decidió el 26-oct), o el
  /// botón.
  ///
  /// [ruta] es el archivo de la base viva y [carpeta] una carpeta de trabajo;
  /// la copia se borra al terminar, salga como salga. [porParte] existe para
  /// que el banco pueda probar varias partes con una base chica.
  Future<({Resultado resultado, RespaldoEnLaNube? manifiesto})>
  subirRespaldoCompleto({
    required Base base,
    required String ruta,
    required String carpeta,
    void Function(int hechas, int total)? alAvanzar,
    int? ahora,
    int porParte = bytesPorParte,
  }) async {
    final c = guarda.credencial;
    final puede =
        c != null &&
        (c.completa || (c.identificaProyecto && (sesion?.hay ?? false)));
    if (!puede) {
      return (
        resultado: const Resultado.mal(
          'La nube no está configurada.',
          esCulpaNuestra: true,
        ),
        manifiesto: null,
      );
    }
    final creado = ahora ?? DateTime.now().millisecondsSinceEpoch;
    final destino = '$carpeta/nube-$creado.db';
    try {
      final copia = hacerCopiaSaneada(base: base, ruta: ruta, destino: destino);
      final empaque = empacar(
        File(copia.ruta).readAsBytesSync(),
        porParte: porParte,
      );
      final manifiesto = RespaldoEnLaNube(
        id: idDeRespaldo(_quien(c), creado),
        creado: creado,
        sello: selloApp,
        esquema: versionEsquema,
        bytesOriginal: empaque.bytesOriginal,
        bytesComprimido: empaque.bytesComprimido,
        partes: empaque.partes.length,
        resumen:
            revisarRespaldo(viva: base, ruta: copia.ruta).candidato?.resumen ??
            '',
      );
      final r = await subida.subirRespaldo(
        credencial: c,
        manifiesto: manifiesto,
        partes: empaque.partes,
        sesion: sesion,
        alAvanzar: alAvanzar,
      );
      if (!r.ok) {
        bitacora.anotar(
          Origen.sistema,
          'El respaldo completo no subió: ${r.falla}',
        );
      }
      return (resultado: r, manifiesto: r.ok ? manifiesto : null);
    } on SecretoEnLaCopia catch (e) {
      return (
        resultado: Resultado.mal('$e', esCulpaNuestra: true),
        manifiesto: null,
      );
    } on FormatException catch (e) {
      return (
        resultado: Resultado.mal(e.message, esCulpaNuestra: true),
        manifiesto: null,
      );
    } finally {
      final f = File(destino);
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// SINCRONIZAR (`sitd-47`, Mauro: «podría llamarse sincronizar, y al
  /// mismo tiempo baja lo que falta»). Un botón en vez de cinco:
  ///
  /// 1. sube lo pendiente (reportes y calibraciones);
  /// 2. baja el respaldo completo MÁS NUEVO de la nube y lo SUMA: entra lo
  ///    que el teléfono no tiene y no se pierde nada (lo repetido gana el del
  ///    teléfono, como siempre);
  /// 3. si después de eso el teléfono tiene algo que esa copia no
  ///    (`loQueFaltaEnElRespaldo`), sube una copia entera nueva. Si no, no
  ///    sube nada: cada copia es la base entera y gastaría cupo para nada.
  ///
  /// Así dos teléfonos con la misma cuenta quedan con lo mismo: el primero
  /// sube, el segundo baja lo del primero, suma lo suyo y sube la unión.
  /// Reemplazar NO está acá: es lo único que pierde datos, y queda a mano.
  ///
  /// Desde `sitd-50` corre SOLA al abrir la aplicación y al cerrar cada viaje
  /// (Mauro: «sí, avanzá con las dos»), y una sola a la vez: si ya hay una
  /// corriendo, la segunda espera la misma. Y al final borra las copias
  /// viejas: ver [_borrarViejos].
  Future<Sincronizado> sincronizar({
    required Base base,
    required String ruta,
    required String carpeta,
    void Function(String que)? alAvanzar,
    int? ahora,
    int porParte = bytesPorParte,
  }) {
    final enCurso = _sincronizando;
    if (enCurso != null) return enCurso;
    final nueva = _sincronizar(
      base: base,
      ruta: ruta,
      carpeta: carpeta,
      alAvanzar: alAvanzar,
      ahora: ahora,
      porParte: porParte,
    ).whenComplete(() => _sincronizando = null);
    return _sincronizando = nueva;
  }

  Future<Sincronizado>? _sincronizando;

  /// Cuántas copias completas quedan siempre en la nube, las más nuevas.
  static const int respaldosQueQuedan = 3;

  /// Y ninguna se borra antes de esto: es lo mismo que pide la regla, para
  /// que una credencial filtrada no pueda vaciar la semana.
  static const int diasAntesDeBorrar = 7;

  Future<Sincronizado> _sincronizar({
    required Base base,
    required String ruta,
    required String carpeta,
    void Function(String que)? alAvanzar,
    int? ahora,
    required int porParte,
  }) async {
    alAvanzar?.call('Subiendo lo pendiente…');
    final pendientes = await subirPendientes();
    final c = guarda.credencial;
    if (c == null) {
      return Sincronizado(
        pendientes: pendientes,
        falla: 'La nube no está configurada.',
      );
    }
    alAvanzar?.call('Mirando qué hay en la nube…');
    final l = await subida.listarRespaldos(
      credencial: c,
      sesion: sesion,
      masNuevosPrimero: true,
    );
    if (l.falla != null) {
      return Sincronizado(pendientes: pendientes, falla: l.falla);
    }
    RespaldoEnLaNube? ultimo;
    for (final r in l.lista) {
      if (ultimo == null || r.creado > ultimo.creado) ultimo = r;
    }

    // sitd-49: se suman TODOS los que todavía no se sumaron acá, no sólo el
    // último. Con sólo el último, el Note 9 comparó contra su propia copia y
    // nunca trajo lo que el Redmi 15 había subido antes (26-oct). Sumar es
    // idempotente, así que lo ya sumado se anota y no se vuelve a bajar.
    final sumados = {
      ...(base.leerAjuste(claveDeRespaldosSumados) ?? '')
          .split(',')
          .where((x) => x.isNotEmpty),
    };
    final porSumar = [
      for (final r in l.lista)
        if (!sumados.contains(r.id) && r.esquema <= versionEsquema) r,
    ]..sort((a, b) => a.creado.compareTo(b.creado));
    Sumado? traido;
    var viajes = 0, puntos = 0, cargas = 0, cargasRepetidas = 0;
    var viajesRepetidos = 0, eventos = 0;
    var hayQueSubir = true;
    for (final r in {...porSumar, ?ultimo}) {
      final b = await bajarRespaldoCompleto(
        respaldo: r,
        carpeta: carpeta,
        alAvanzar: (h, t) => alAvanzar?.call('Bajando: parte $h de $t'),
      );
      if (b.ruta == null) {
        return Sincronizado(
          pendientes: pendientes,
          comparado: ultimo,
          traido: traido,
          falla: b.falla,
        );
      }
      try {
        if (!sumados.contains(r.id) &&
            revisarRespaldo(viva: base, ruta: b.ruta!).sePuede) {
          alAvanzar?.call('Sumando lo que falta…');
          final t = sumarRespaldo(
            viva: base,
            ruta: b.ruta!,
            carpetaDeTrabajo: carpeta,
          );
          if (!t.salioBien) {
            return Sincronizado(
              pendientes: pendientes,
              comparado: ultimo,
              traido: t,
              falla: t.problema,
            );
          }
          viajes += t.viajes;
          viajesRepetidos += t.viajesRepetidos;
          puntos += t.puntos;
          cargas += t.cargas;
          cargasRepetidas += t.cargasRepetidas;
          eventos += t.eventos;
          sumados.add(r.id);
          base.escribirAjuste(claveDeRespaldosSumados, sumados.join(','));
        }
        // Con el más nuevo se compara: si acá hay algo que allá no, se sube.
        if (r == ultimo) {
          final falta = loQueFaltaEnElRespaldo(viva: base, ruta: b.ruta!);
          hayQueSubir =
              falta.problema != null || falta.filas > 0 || falta.puntos > 0;
        }
      } finally {
        final f = File(b.ruta!);
        if (f.existsSync()) f.deleteSync();
      }
    }
    if (ultimo != null) {
      traido = Sumado(
        viajes: viajes,
        viajesRepetidos: viajesRepetidos,
        puntos: puntos,
        cargas: cargas,
        cargasRepetidas: cargasRepetidas,
        eventos: eventos,
      );
    }
    if (!hayQueSubir) {
      final borrados = await _borrarViejos(
        c,
        l.lista,
        sumados,
        ahora ?? DateTime.now().millisecondsSinceEpoch,
      );
      return Sincronizado(
        pendientes: pendientes,
        comparado: ultimo,
        traido: traido,
        alDia: true,
        borrados: borrados,
      );
    }
    final s = await subirRespaldoCompleto(
      base: base,
      ruta: ruta,
      carpeta: carpeta,
      alAvanzar: (h, t) => alAvanzar?.call('Subiendo la copia: parte $h de $t'),
      ahora: ahora,
      porParte: porParte,
    );
    // La copia propia ya tiene todo lo de acá: no hay que volver a sumarla.
    final propio = s.manifiesto;
    var borrados = 0;
    if (propio != null) {
      sumados.add(propio.id);
      base.escribirAjuste(claveDeRespaldosSumados, sumados.join(','));
      borrados = await _borrarViejos(
        c,
        [...l.lista, propio],
        sumados,
        ahora ?? DateTime.now().millisecondsSinceEpoch,
      );
    }
    return Sincronizado(
      pendientes: pendientes,
      comparado: ultimo,
      traido: traido,
      borrados: borrados,
      subido: s.manifiesto,
      falla: s.manifiesto == null ? s.resultado.falla : null,
    );
  }

  /// Borra las copias de la nube que ya no hacen falta (`sitd-50`). Se llama
  /// SÓLO cuando la copia más nueva de la nube tiene todo lo de este teléfono
  /// (recién subida, o comparada y al día), y borra una sólo si:
  /// · no es de las [respaldosQueQuedan] más nuevas;
  /// · tiene más de [diasAntesDeBorrar] días;
  /// · ya se sumó en este teléfono, o sea que lo suyo está acá y por eso en
  ///   la copia más nueva.
  /// Si una falla, se deja para la próxima: no frena nada.
  Future<int> _borrarViejos(
    Credencial c,
    List<RespaldoEnLaNube> todos,
    Set<String> sumados,
    int ahora,
  ) async {
    final orden = [...todos]..sort((a, b) => b.creado.compareTo(a.creado));
    final limite = ahora - diasAntesDeBorrar * 24 * 3600 * 1000;
    var borrados = 0;
    for (final r in orden.skip(respaldosQueQuedan)) {
      if (r.creado >= limite || !sumados.contains(r.id)) continue;
      final falla = await subida.borrarRespaldo(
        credencial: c,
        respaldo: r,
        sesion: sesion,
      );
      if (falla == null) {
        borrados++;
      } else {
        bitacora.anotar(Origen.sistema, 'No se borró ${r.id}: $falla');
        break; // si la regla no deja, no deja ninguno
      }
    }
    if (borrados > 0) {
      bitacora.anotar(
        Origen.sistema,
        'Sincronizar borró $borrados ${borrados == 1 ? 'copia vieja' : 'copias viejas'} de la nube.',
      );
    }
    return borrados;
  }

  /// Baja [respaldo] y lo deja como archivo en [carpeta], listo para entrar
  /// por el camino de siempre: `revisarRespaldo` y el cartel de Sumar o
  /// Reemplazar. **Este método no toca la base viva**, a propósito: meter un
  /// respaldo es una decisión que se toma mirando los números de los dos
  /// lados, y eso es de la pantalla.
  Future<({String? ruta, String? falla})> bajarRespaldoCompleto({
    required RespaldoEnLaNube respaldo,
    required String carpeta,
    void Function(int hechas, int total)? alAvanzar,
  }) async {
    final c = guarda.credencial;
    if (c == null) return (ruta: null, falla: 'La nube no está configurada.');
    final b = await subida.bajarRespaldo(
      credencial: c,
      respaldo: respaldo,
      sesion: sesion,
      alAvanzar: alAvanzar,
    );
    if (b.base == null) return (ruta: null, falla: b.falla);
    final ruta = '$carpeta/${respaldo.id}.db';
    File(ruta).writeAsBytesSync(b.base!, flush: true);
    return (ruta: ruta, falla: null);
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
    'telefono': v.telefono,
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
  /// Dónde se anota qué calibraciones ya subieron (`tipo@inicio`, una lista).
  static const String claveDeCalibracionesSubidas = 'calibraciones_subidas';

  /// Los respaldos de la nube que ya se sumaron en este teléfono (`sitd-49`).
  /// No empieza con `nube_`: no es un secreto y puede viajar en una copia.
  static const String claveDeRespaldosSumados = 'respaldos_sumados';

  /// Sube cada calibración TERMINADA que no subió, como un documento propio
  /// de `reportes/`: `<quien>-cal-<tipo>-<inicio>`. La regla del teléfono
  /// (crear, con `json`, `sello` y `generado`) no cambia, y un 409 es que ya
  /// estaba. La prueba con peso sube cuando se cierra: mientras dura no es un
  /// dato terminado. No lleva coordenadas: se hacen parado.
  Future<({int subidas, int fallaron, String? falla})> _subirCalibraciones(
    Credencial c,
  ) async {
    final reg = calibraciones;
    if (reg == null) return (subidas: 0, fallaron: 0, falla: null);
    final base = reg.base;
    final ya = <String>{
      ...(base.leerAjuste(claveDeCalibracionesSubidas) ?? '')
          .split(',')
          .where((s) => s.isNotEmpty),
    };
    var subidas = 0;
    var fallaron = 0;
    String? falla;
    for (final cal in reg.ultimas(cuantas: 100).reversed) {
      final llave = '${cal.tipo}@${cal.inicio}';
      if (cal.abierta || ya.contains(llave)) continue;
      final r = await subida.subir(
        credencial: c,
        id: '${_quien(c)}-cal-${cal.tipo}-${cal.inicio}',
        reporte: reporteDeCalibracion(
          cal,
          sello: selloApp,
          ahora: DateTime.now().millisecondsSinceEpoch,
          telefono: base.leerAjuste(claveDelTelefono),
        ),
        sesion: sesion,
      );
      if (r.ok) {
        ya.add(llave);
        base.escribirAjuste(claveDeCalibracionesSubidas, ya.join(','));
        subidas++;
      } else {
        fallaron++;
        falla ??= r.falla;
        if (r.esCulpaNuestra) break;
      }
    }
    if (subidas > 0) {
      bitacora.anotar(Origen.sistema, 'Subieron $subidas calibraciones.');
    }
    return (subidas: subidas, fallaron: fallaron, falla: falla);
  }

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
