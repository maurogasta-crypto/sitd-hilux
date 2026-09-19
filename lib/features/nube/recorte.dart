import 'dart:convert';

/// El tope de un documento de Firestore es **1 MiB** (1.048.576 bytes),
/// contando nombres de campo y valores. Acá se apunta bastante más abajo.
///
/// **Por qué tan abajo:** el reporte va en un campo de texto, y al lado viajan
/// el sello y la marca de tiempo; además el límite se cuenta en bytes UTF-8 y
/// un reporte con tildes ocupa más que su largo en caracteres. Con 700 000 se
/// entra siempre, y lo que se pierde por recortar de más es bajísimo frente a
/// un documento rechazado que la cola reintentaría para siempre.
const int topeDelDocumento = 700000;

/// Qué hubo que sacar para que entrara. `null` si no hubo que sacar nada.
class Recorte {
  final int bytesOriginales;
  final int bytesFinales;
  final bool bitacoraQuitada;

  /// Cuántas ventanas de vibración tenía y cuántas quedaron.
  final int vibracionesAntes;
  final int vibracionesDespues;

  /// `true` si ni recortando entró. No debería pasar nunca —un viaje de
  /// catorce horas—, y si pasa hay que saberlo y no quedarse reintentando.
  final bool noEntro;

  const Recorte({
    required this.bytesOriginales,
    required this.bytesFinales,
    this.bitacoraQuitada = false,
    this.vibracionesAntes = 0,
    this.vibracionesDespues = 0,
    this.noEntro = false,
  });

  bool get huboRecorte =>
      bitacoraQuitada || vibracionesDespues < vibracionesAntes;

  Map<String, dynamic> aMapa() => {
    'bytesOriginales': bytesOriginales,
    'bytesFinales': bytesFinales,
    'bitacoraQuitada': bitacoraQuitada,
    'vibracionesAntes': vibracionesAntes,
    'vibracionesDespues': vibracionesDespues,
    'noEntro': noEntro,
  };
}

/// El reporte listo para subir, y qué hubo que sacarle.
class ParaSubir {
  final Map<String, dynamic> reporte;
  final Recorte recorte;

  const ParaSubir(this.reporte, this.recorte);
}

/// Deja el reporte abajo del tope, sacando lo menos valioso primero.
///
/// **El orden no es casual, y es la decisión entera de este archivo.** Se saca
/// primero lo que se puede volver a obtener y último lo que no:
///
///  1. **la bitácora** — es diagnóstico del intercambio con el sistema, y en
///     un viaje largo que anduvo bien no dice nada que no diga el resto;
///  2. **las ventanas de vibración, diezmadas parejo** — se queda una de cada
///     N a lo largo del viaje entero, no las primeras N. Un viaje recortado
///     por el principio mentiría sobre a qué velocidad anduvo.
///
/// **Y nunca se recorta en silencio.** El documento lleva escrito qué se sacó
/// y cuánto, así que un vector que falta se puede explicar seis meses después
/// en vez de parecer un hueco raro en los datos.
ParaSubir recortarParaSubir(
  Map<String, dynamic> original, {
  int tope = topeDelDocumento,
}) {
  final bytesOriginales = _pesar(original);
  final antes = _cuantasVentanas(original);

  if (bytesOriginales <= tope) {
    return ParaSubir(
      original,
      Recorte(
        bytesOriginales: bytesOriginales,
        bytesFinales: bytesOriginales,
        vibracionesAntes: antes,
        vibracionesDespues: antes,
      ),
    );
  }

  // De acá en adelante SIEMPRE lleva la nota de recorte, así que se mide el
  // documento final y no el intermedio. **Ése era el error**: el banco lo
  // encontró con 500 ventanas y un tope de 1500 — la versión diezmada entraba
  // por 1659 bytes y la nota, que se agregaba después, la pasaba de largo.
  final sinBitacora = Map<String, dynamic>.from(original)..remove('bitacora');
  final bitacoraQuitada = original.containsKey('bitacora');

  ParaSubir? probar(int? diezmar) {
    final cuerpo = diezmar == null
        ? sinBitacora
        : _conVibracionDiezmada(sinBitacora, diezmar);
    final quedaron = _cuantasVentanas(cuerpo);
    final doc = _conNota(cuerpo, bitacoraQuitada, antes, quedaron);
    final bytes = _pesar(doc);
    if (bytes > tope) return null;
    return ParaSubir(
      doc,
      Recorte(
        bytesOriginales: bytesOriginales,
        bytesFinales: bytes,
        bitacoraQuitada: bitacoraQuitada,
        vibracionesAntes: antes,
        vibracionesDespues: quedaron,
      ),
    );
  }

  // 1. Sin la bitácora, con toda la vibración.
  final soloSinBitacora = probar(null);
  if (soloSinBitacora != null) return soloSinBitacora;

  // 2. Diezmando parejo, cada vez más.
  for (final n in const [2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233]) {
    final r = probar(n);
    if (r != null) return r;
  }

  // 3. Sin una sola ventana. Si ni así entra, el problema es otro y hay que
  //    decirlo en vez de reintentar para siempre.
  final pelado = probar(0);
  if (pelado != null) return pelado;

  final cuerpo = _conVibracionDiezmada(sinBitacora, 0);
  final doc = _conNota(cuerpo, bitacoraQuitada, antes, 0);
  return ParaSubir(
    doc,
    Recorte(
      bytesOriginales: bytesOriginales,
      bytesFinales: _pesar(doc),
      bitacoraQuitada: bitacoraQuitada,
      vibracionesAntes: antes,
      vibracionesDespues: 0,
      noEntro: true,
    ),
  );
}

int _pesar(Object? x) => utf8.encode(jsonEncode(x)).length;

int _cuantasVentanas(Map<String, dynamic> r) {
  var n = 0;
  for (final v in (r['viajes'] as List? ?? const [])) {
    n += ((v as Map)['vibraciones'] as List? ?? const []).length;
  }
  return n;
}

/// `n == 0` saca todas. Si no, deja una de cada `n`, repartidas a lo largo del
/// viaje: el índice que sobrevive es el múltiplo de `n`.
Map<String, dynamic> _conVibracionDiezmada(Map<String, dynamic> r, int n) {
  final viajes = <dynamic>[];
  for (final v in (r['viajes'] as List? ?? const [])) {
    final copia = Map<String, dynamic>.from(v as Map);
    final ventanas = copia['vibraciones'] as List? ?? const [];
    copia['vibraciones'] = n == 0
        ? const []
        : [
            for (var i = 0; i < ventanas.length; i++)
              if (i % n == 0) ventanas[i],
          ];
    viajes.add(copia);
  }
  return Map<String, dynamic>.from(r)..['viajes'] = viajes;
}

Map<String, dynamic> _conNota(
  Map<String, dynamic> r,
  bool bitacoraQuitada,
  int antes,
  int despues,
) => Map<String, dynamic>.from(r)
  ..['recorte'] = {
    'porque':
        'El reporte no entraba en un documento de Firestore (tope de 1 MB). '
        'Se sacó lo que se puede reconstruir antes que lo que no.',
    'bitacoraQuitada': bitacoraQuitada,
    'ventanasDeVibracionAntes': antes,
    'ventanasDeVibracionDespues': despues,
  };
