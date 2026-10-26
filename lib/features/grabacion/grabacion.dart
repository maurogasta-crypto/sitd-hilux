import 'dart:convert';
import 'dart:typed_data';

import '../../core/bitacora.dart';
import '../../core/db/base.dart';
import '../audio/regimen.dart' show hzAudio;
import '../vibracion/sacudon.dart';
import '../vibracion/ventana.dart' show cubetaDe, nombreDeCubeta;

/// Las GRABACIONES: diez segundos de sonido y de acelerómetro crudo
/// (`sitd-55`, `hilux:D7`).
///
/// **Da vuelta una regla de fondo, a pedido de Mauro y con la objeción sobre
/// la mesa.** Hasta `sitd-54` el micrófono no guardaba sonido: sólo números.
/// El 26-oct Mauro: «sí, avanzá con las dos, y tener registro del audio sirve
/// como respaldo para analizar el fallo… como prueba para descargar un mal
/// funcionamiento del software». Lo que lo contiene:
///
///  · **Diez segundos, y sólo cuando hace falta**: cuando una línea que se
///    repite se salió de lo normal en el viaje anterior (una por viaje), o
///    cuando alguien toca «Grabar 10 s» (hasta [maximoAManoPorDia] por día).
///  · **Nunca con una llamada ni con música**: es lo mismo que pide la
///    compuerta del micrófono. Una automática, además, a más de 30 km/h y en
///    la cubeta de la línea marcada: a esa velocidad lo que entra es motor y
///    ruta. Si algo de eso cambia a mitad de camino, se tira lo juntado y se
///    espera.
///  · **Va a una colección propia de la base de la Hilux** (`grabaciones/`),
///    que lee sólo esta cuenta y el agente. NO va al reporte para desarrollo
///    ni a las copias completas: cuando subió, el sonido se borra del
///    teléfono y queda la ficha.
///
/// El acelerómetro va crudo —los tres ejes y el módulo, a lo que entregue,
/// unos 200 Hz— porque el espectro de 5 s que se guarda en cada ventana
/// resume, y para entender un caso raro hace falta la señal.
class Grabacion {
  final int? id;
  final int? viaje;
  final int t;
  final String motivo;
  final double? kmh;
  final int? marcha;
  final int hzAudio;

  /// PCM de 16 bits, little-endian. `null` cuando ya subió.
  final Uint8List? audio;

  final double? hzVib;

  /// Cuatro `float32` por muestra: módulo, x, y, z (NaN si no hay ejes).
  final Uint8List? vibracion;

  final bool subida;

  const Grabacion({
    this.id,
    this.viaje,
    required this.t,
    required this.motivo,
    this.kmh,
    this.marcha,
    required this.hzAudio,
    this.audio,
    this.hzVib,
    this.vibracion,
    this.subida = false,
  });

  double get segundosDeAudio => audio == null ? 0 : audio!.length / 2 / hzAudio;

  int get muestrasDeVibracion =>
      vibracion == null ? 0 : vibracion!.length ~/ 16;
}

/// Cuántas grabaciones a mano por día. Son para un caso, no para usarlas de
/// grabador: con diez alcanza para cualquier tarde de pruebas.
const int maximoAManoPorDia = 10;

/// Cuántos segundos dura cada una.
const int segundosDeGrabacion = 10;

/// Desde qué velocidad se graba sola.
const double kmhMinimaParaGrabarSola = 30;

/// Lo que se pide grabar.
class PedidoDeGrabar {
  final String motivo;

  /// La cubeta de la línea marcada; `null` en una a mano.
  final int? cubeta;
  final bool aMano;

  const PedidoDeGrabar(this.motivo, {this.cubeta, this.aMano = false});

  Map<String, dynamic> aMapa() => {'motivo': motivo, 'cubeta': cubeta};

  static PedidoDeGrabar? deTexto(String? t) {
    if (t == null || t.isEmpty) return null;
    try {
      final m = jsonDecode(t) as Map<String, dynamic>;
      final motivo = m['motivo'] as String?;
      if (motivo == null) return null;
      return PedidoDeGrabar(motivo, cubeta: (m['cubeta'] as num?)?.toInt());
    } catch (_) {
      return null;
    }
  }
}

class RegistroDeGrabaciones {
  final Base base;

  RegistroDeGrabaciones(this.base);

  /// Dónde queda la grabación automática que espera su viaje.
  static const String clavePendiente = 'grabar_pendiente';

  PedidoDeGrabar? get pendiente =>
      PedidoDeGrabar.deTexto(base.leerAjuste(clavePendiente));

  void pedir(PedidoDeGrabar p) =>
      base.escribirAjuste(clavePendiente, jsonEncode(p.aMapa()));

  void olvidarPendiente() => base.escribirAjuste(clavePendiente, '');

  int guardar(Grabacion g) {
    // Un viaje que ya no está (descartado mientras grababa) no se nombra:
    // la grabación vale igual.
    final viaje =
        g.viaje != null &&
            base.db.select('SELECT 1 FROM viajes WHERE id = ?', [
              g.viaje,
            ]).isNotEmpty
        ? g.viaje
        : null;
    base.db.execute(
      'INSERT INTO grabaciones (viaje, t, motivo, kmh, marcha, hz_audio, '
      'audio, hz_vib, vibracion, subida) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        viaje,
        g.t,
        g.motivo,
        g.kmh,
        g.marcha,
        g.hzAudio,
        g.audio,
        g.hzVib,
        g.vibracion,
      ],
    );
    return base.db.lastInsertRowId;
  }

  List<Grabacion> sinSubir() => [
    for (final f in base.db.select(
      'SELECT * FROM grabaciones WHERE subida = 0 ORDER BY t',
    ))
      _de(f),
  ];

  List<Grabacion> ultimas([int cuantas = 20]) => [
    for (final f in base.db.select(
      'SELECT id, viaje, t, motivo, kmh, marcha, hz_audio, hz_vib, subida '
      'FROM grabaciones ORDER BY t DESC LIMIT ?',
      [cuantas],
    ))
      _de(f),
  ];

  /// Ya subió: se borra el sonido y la señal, queda la ficha.
  void marcarSubida(int id) => base.db.execute(
    'UPDATE grabaciones SET subida = 1, audio = NULL, vibracion = NULL '
    'WHERE id = ?',
    [id],
  );

  /// Cuántas a mano desde [desde] (ms).
  int aManoDesde(int desde) =>
      base.db.select(
            "SELECT COUNT(*) AS n FROM grabaciones WHERE t >= ? "
            "AND motivo LIKE 'a mano%'",
            [desde],
          ).first['n']
          as int;

  static Grabacion _de(dynamic f) => Grabacion(
    id: f['id'] as int,
    viaje: f['viaje'] as int?,
    t: f['t'] as int,
    motivo: f['motivo'] as String,
    kmh: (f['kmh'] as num?)?.toDouble(),
    marcha: f['marcha'] as int?,
    hzAudio: f['hz_audio'] as int,
    audio: _bytes(_campo(f, 'audio')),
    hzVib: (f['hz_vib'] as num?)?.toDouble(),
    vibracion: _bytes(_campo(f, 'vibracion')),
    subida: (f['subida'] as int) == 1,
  );

  static Object? _campo(dynamic f, String c) {
    try {
      return f[c];
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _bytes(Object? o) => o is Uint8List
      ? o
      : o is List<int>
      ? Uint8List.fromList(o)
      : null;
}

/// El PCM de los trozos, como bytes de 16 bits little-endian.
Uint8List pcmABytes(List<List<int>> trozos) {
  final n = trozos.fold<int>(0, (s, t) => s + t.length);
  final d = ByteData(n * 2);
  var i = 0;
  for (final t in trozos) {
    for (final m in t) {
      d.setInt16(i, m.clamp(-32768, 32767), Endian.little);
      i += 2;
    }
  }
  return d.buffer.asUint8List();
}

/// Los sacudones como cuatro `float32` cada uno: módulo, x, y, z.
Uint8List sacudonesABytes(List<Sacudon> s) {
  final d = ByteData(s.length * 16);
  for (var i = 0; i < s.length; i++) {
    d.setFloat32(i * 16, s[i].magnitud, Endian.little);
    d.setFloat32(i * 16 + 4, s[i].x ?? double.nan, Endian.little);
    d.setFloat32(i * 16 + 8, s[i].y ?? double.nan, Endian.little);
    d.setFloat32(i * 16 + 12, s[i].z ?? double.nan, Endian.little);
  }
  return d.buffer.asUint8List();
}

/// Junta los trozos del micrófono hasta tener [segundosDeGrabacion], si se
/// pidió una grabación y se dan las condiciones. Lo alimenta el servicio de
/// audio con cada segundo que escucha.
class Grabador {
  final RegistroDeGrabaciones registro;

  /// El acelerómetro crudo entre dos instantes (ms), del servicio de
  /// vibración.
  final List<Sacudon> Function(int desde, int hasta) acelerometro;

  final int Function() ahora;

  Grabador({
    required this.registro,
    required this.acelerometro,
    int Function()? reloj,
  }) : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  PedidoDeGrabar? _pedido;
  int? _viaje;
  final List<List<int>> _trozos = [];
  int? _tInicio;
  double? _kmhInicio;

  /// Lo que está pedido ahora (para la pantalla).
  PedidoDeGrabar? get pedido => _pedido;

  /// Cuántos segundos lleva juntados.
  int get juntados => _trozos.length;

  /// Al empezar un viaje: si quedó una automática pedida, se espera ésa.
  void empezarViaje(int viaje) {
    _viaje = viaje;
    _trozos.clear();
    final p = registro.pendiente;
    if (p != null && (_pedido == null || !_pedido!.aMano)) _pedido = p;
  }

  void terminarViaje() {
    _viaje = null;
    _trozos.clear();
    // Una a mano que no llegó a grabarse no se arrastra al viaje que viene.
    if (_pedido?.aMano ?? false) _pedido = null;
  }

  /// «Grabar 10 s». Devuelve por qué no, o `null` si quedó pedida.
  String? pedirAMano() {
    final d = DateTime.fromMillisecondsSinceEpoch(ahora());
    final hoy = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    if (registro.aManoDesde(hoy) >= maximoAManoPorDia) {
      return 'Ya van $maximoAManoPorDia grabaciones hoy.';
    }
    _pedido = PedidoDeGrabar('a mano, ${segundosDeGrabacion}s', aMano: true);
    _trozos.clear();
    return null;
  }

  /// Un segundo del micrófono. Devuelve la grabación si con éste se completó.
  Grabacion? trozo(
    List<int> pcm, {
    required int t,
    required double? kmh,
    required int? marcha,
    required bool musica,
    required bool llamada,
  }) {
    final p = _pedido;
    if (p == null) return null;
    final sirve =
        !musica &&
        !llamada &&
        (p.aMano ||
            (kmh != null &&
                kmh >= kmhMinimaParaGrabarSola &&
                (p.cubeta == null || cubetaDe(kmh) == p.cubeta)));
    if (!sirve) {
      _trozos.clear();
      return null;
    }
    if (_trozos.isEmpty) {
      _tInicio = t - 1000;
      _kmhInicio = kmh;
    }
    _trozos.add(List<int>.from(pcm));
    if (_trozos.length < segundosDeGrabacion) return null;

    final desde = _tInicio!;
    final vib = acelerometro(desde, t);
    final hzVib = vib.length > 1
        ? (vib.length - 1) * 1000 / (vib.last.t - vib.first.t)
        : null;
    final media = kmh != null && _kmhInicio != null
        ? (kmh + _kmhInicio!) / 2
        : kmh;
    final g = Grabacion(
      viaje: _viaje,
      t: t,
      motivo: p.motivo,
      kmh: media,
      marcha: marcha,
      hzAudio: hzAudio,
      audio: pcmABytes(_trozos),
      hzVib: hzVib != null && hzVib.isFinite ? hzVib : null,
      vibracion: vib.isEmpty ? null : sacudonesABytes(vib),
    );
    try {
      registro.guardar(g);
    } catch (e) {
      // Guardar no puede tirar abajo el micrófono: se dice y se sigue.
      bitacora.anotar(Origen.sistema, 'La grabación no se pudo guardar: $e');
      _pedido = null;
      _trozos.clear();
      return null;
    }
    if (!p.aMano) registro.olvidarPendiente();
    _pedido = null;
    _trozos.clear();
    bitacora.anotar(
      Origen.sistema,
      'Grabados $segundosDeGrabacion s de sonido y acelerómetro (${p.motivo})'
      '${media != null ? ' a ${media.toStringAsFixed(0)} km/h' : ''}.',
    );
    return g;
  }
}

/// El motivo de una grabación automática, en palabras.
String motivoDeLinea(String linea, int cubeta, String que) =>
    'línea $linea ${que == 'crece' ? 'creció' : 'se corrió'} a '
    '${nombreDeCubeta(cubeta)}';

/// Los campos de Firestore de una grabación. Sin coordenadas: dónde estaba
/// la camioneta no hace falta para oír el motor.
Map<String, dynamic> camposDeGrabacion(
  Grabacion g, {
  required String sello,
  String? telefono,
}) => {
  't': {'integerValue': '${g.t}'},
  if (g.viaje != null) 'viaje': {'integerValue': '${g.viaje}'},
  'motivo': {'stringValue': g.motivo},
  if (g.kmh != null) 'kmh': {'doubleValue': g.kmh},
  if (g.marcha != null) 'marcha': {'integerValue': '${g.marcha}'},
  'hzAudio': {'integerValue': '${g.hzAudio}'},
  if (g.hzVib != null) 'hzVib': {'doubleValue': g.hzVib},
  if (g.audio != null) 'audio': {'bytesValue': base64Encode(g.audio!)},
  if (g.vibracion != null)
    'vibracion': {'bytesValue': base64Encode(g.vibracion!)},
  'sello': {'stringValue': sello},
  if (telefono != null) 'telefono': {'stringValue': telefono},
};
