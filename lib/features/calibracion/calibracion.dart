/// Las CALIBRACIONES: lo que se mide en el garage para leer después los
/// viajes (`sitd-45`).
///
/// ## Por qué existe
///
/// Lo pidió Mauro el 2026-10-25: «un botón que diga calibración… el registro
/// de todos los datos que pueden hacerse en garage antes de arrancar un
/// viaje». La vibración de un viaje es la suma de la rueda, el cardán, el
/// motor, el camino y el soporte, y separarlos con datos de ruta solos no se
/// puede (`MEDICION.md`): hace falta medir cada pieza por su lado, en
/// condiciones conocidas, y guardar eso como REFERENCIA.
///
/// ## Los tipos de hoy
///
/// - **rueda**: tantas vueltas son tantos metros, rodando en el piso. Da la
///   frecuencia exacta de la rueda (`rueda.dart`).
/// - **peso**: un peso puesto en una rueda, de cuándo a cuándo. Todo lo que
///   se mida en ese tramo es «con peso», y la ronda lo compara contra el antes
///   y el después: es la única forma de saber si el detector ve un
///   desbalanceo de verdad.
/// - **motor**: la camioneta parada, a ralentí, 1000, 1500 y 2000 RPM. Da cómo
///   suena y cómo vibra el motor solo, sin camino.
///
/// Un tipo nuevo entra como otra entrada de [tiposDeCalibracion] y su `datos`:
/// la tabla no cambia.
///
/// **Ni una coordenada**: se hacen parado, viajan en el reporte, y el banco
/// lo comprueba con el resto del reporte.
library;

import 'dart:convert';

import '../../core/db/base.dart';
import '../vibracion/rueda.dart';

/// Los tipos que existen, con el nombre que ve la persona.
const Map<String, String> tiposDeCalibracion = {
  'rueda': 'Vuelta de la rueda',
  'peso': 'Prueba con un peso en una rueda',
  'motor': 'Motor parado: ralentí, 1000, 1500 y 2000 RPM',
};

/// Las variantes de la prueba del motor (`sitd-46`). La de siempre no lleva
/// nombre; con el aire acondicionado prendido el compresor carga el motor y
/// suma su propio zumbido, y es lo que hay que conocer para no confundirlo
/// con una falla.
const Map<String, String> variantesDelMotor = {
  'aire': 'con el aire acondicionado prendido',
};

/// Las cuatro ruedas, como las nombra quien está parado al lado.
const List<String> ruedas = [
  'delantera izquierda',
  'delantera derecha',
  'trasera izquierda',
  'trasera derecha',
];

class Calibracion {
  final int? id;
  final String tipo;
  final int inicio;

  /// `null` mientras dura (la prueba del peso, hasta que se saca).
  final int? fin;
  final Map<String, dynamic> datos;
  final String? notas;

  const Calibracion({
    required this.tipo,
    required this.inicio,
    this.id,
    this.fin,
    this.datos = const {},
    this.notas,
  });

  bool get abierta => fin == null;

  /// Para el reporte. Lleva todo: no hay nada acá que no se pueda mandar.
  Map<String, dynamic> aMapa() => {
    'tipo': tipo,
    'inicio': inicio,
    'fin': fin,
    'datos': datos,
    if (notas != null && notas!.isNotEmpty) 'notas': notas,
  };
}

// ─── La rueda ────────────────────────────────────────────────────────────────

/// Lo que se escribe después de rodar la camioneta en el garage.
///
/// Devuelve `null` con el porqué si no cierra: cero vueltas, metros negativos,
/// o una vuelta que no es de esta rueda (ver `circunferenciaCreible`). Un
/// número mal tipeado no puede pasar a ser la frecuencia de la rueda.
({Map<String, dynamic>? datos, String? problema}) medidaDeRueda({
  required double? vueltas,
  required double? metros,
  double? presionPsi,
  String? carga,
}) {
  if (vueltas == null || !vueltas.isFinite || vueltas <= 0) {
    return (datos: null, problema: 'Falta cuántas vueltas dio la rueda.');
  }
  if (metros == null || !metros.isFinite || metros <= 0) {
    return (datos: null, problema: 'Falta cuántos metros avanzó.');
  }
  final c = metros / vueltas;
  if (!circunferenciaCreible(c)) {
    return (
      datos: null,
      problema:
          'Da ${c.toStringAsFixed(3)} m por vuelta, y esta rueda anda por '
          '2,39. Revisá las vueltas y los metros.',
    );
  }
  return (
    datos: {
      'vueltas': vueltas,
      'metros': metros,
      'circunferenciaM': double.parse(c.toStringAsFixed(4)),
      'diametroM': double.parse((c / 3.141592653589793).toStringAsFixed(4)),
      if (presionPsi != null && presionPsi > 0) 'presionPsi': presionPsi,
      if (carga != null && carga.trim().isNotEmpty) 'carga': carga.trim(),
    },
    problema: null,
  );
}

// ─── Lo que sube a la nube ───────────────────────────────────────────────────

/// El documento que sube una calibración sola (`sitd-46`): la calibración y
/// con qué vuelta de rueda leía la app en ese momento. Ni una coordenada.
Map<String, dynamic> reporteDeCalibracion(
  Calibracion c, {
  required String sello,
  required int ahora,
  String? telefono,
}) => {
  'reporte': 'calibracion',
  'generado': ahora,
  'app': {'sello': sello},
  'telefono': ?telefono,
  'circunferenciaM': double.parse(circunferencia.toStringAsFixed(4)),
  'circunferenciaMedida': circunferenciaEsMedida,
  'calibracion': c.aMapa(),
};

// ─── El registro ─────────────────────────────────────────────────────────────

class RegistroDeCalibraciones {
  final Base base;

  RegistroDeCalibraciones(this.base);

  int guardar(Calibracion c) {
    base.db.execute(
      'INSERT INTO calibraciones (tipo, inicio, fin, datos, notas) '
      'VALUES (?, ?, ?, ?, ?)',
      [c.tipo, c.inicio, c.fin, jsonEncode(c.datos), c.notas],
    );
    return base.db.lastInsertRowId;
  }

  /// Cierra una abierta (sacaron el peso).
  void cerrar(int id, int fin) => base.db.execute(
    'UPDATE calibraciones SET fin = ? WHERE id = ? AND fin IS NULL',
    [fin, id],
  );

  void borrar(int id) =>
      base.db.execute('DELETE FROM calibraciones WHERE id = ?', [id]);

  /// De la más nueva a la más vieja; de un [tipo] si se pide.
  List<Calibracion> ultimas({String? tipo, int cuantas = 50}) => base.db
      .select(
        tipo == null
            ? 'SELECT * FROM calibraciones ORDER BY inicio DESC LIMIT ?'
            : 'SELECT * FROM calibraciones WHERE tipo = ? '
                  'ORDER BY inicio DESC LIMIT ?',
        tipo == null ? [cuantas] : [tipo, cuantas],
      )
      .map(
        (f) => Calibracion(
          id: f['id'] as int,
          tipo: f['tipo'] as String,
          inicio: f['inicio'] as int,
          fin: f['fin'] as int?,
          datos: _datos(f['datos'] as String?),
          notas: f['notas'] as String?,
        ),
      )
      .toList();

  /// La prueba de peso que está corriendo, si hay una.
  Calibracion? pesoEnCurso() {
    for (final c in ultimas(tipo: 'peso', cuantas: 5)) {
      if (c.abierta) return c;
    }
    return null;
  }

  /// La última vuelta de rueda medida, en metros, o `null` si nunca se midió.
  double? ultimaCircunferencia() {
    for (final c in ultimas(tipo: 'rueda', cuantas: 5)) {
      final m = (c.datos['circunferenciaM'] as num?)?.toDouble();
      if (m != null && circunferenciaCreible(m)) return m;
    }
    return null;
  }

  /// Pone en `rueda.dart` la última medida (o el diámetro de siempre).
  void aplicarRueda() => usarCircunferenciaMedida(ultimaCircunferencia());

  static Map<String, dynamic> _datos(String? texto) {
    if (texto == null || texto.isEmpty) return const {};
    try {
      final m = jsonDecode(texto);
      return m is Map<String, dynamic> ? m : const {};
    } on FormatException {
      return const {};
    }
  }
}
