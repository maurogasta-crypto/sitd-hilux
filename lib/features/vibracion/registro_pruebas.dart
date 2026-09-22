/// Las pruebas del propio sensor, guardadas para poder COMPARAR.
///
/// **Guardarlas es la mitad de la herramienta.** Lo que hay que averiguar no
/// es un número sino cuál de dos soportes sirve más, y eso no se puede hacer
/// con una pantalla en vivo sola: uno mira la primera medición, se baja, ata
/// el teléfono en otro lado, mira la segunda, y para entonces ya no se acuerda
/// de la primera. Con la lista al lado, la comparación se hace mirando.
///
/// No se guarda la señal cruda: lo que entra son los números que salen de
/// `medirCalidad`. Es el mismo criterio que las ventanas de vibración —el
/// vector se guarda, la señal no— y por el mismo motivo: lo crudo ocupa
/// megabytes y lo que se compara es esto.
library;

import '../../core/db/base.dart';
import 'calidad.dart';

/// Una medición guardada, con el contexto sin el cual no significa nada.
class PruebaDeSensor {
  final int? id;
  final int t;

  /// Dónde estaba el teléfono. Texto libre: los soportes que se le ocurran a
  /// Mauro no los puede enumerar este archivo.
  final String soporte;

  /// El período que se PIDIÓ, en milisegundos. Cero es «lo más rápido que
  /// puedas».
  ///
  /// Se guarda aparte de la frecuencia medida porque son dos cosas distintas
  /// y la diferencia entre ellas es justamente el hallazgo: pidiendo 20 ms
  /// el Redmi 15 entrega cada 20,06.
  final int periodoMs;

  /// Qué estaba pasando: motor apagado, ralentí, andando a 80.
  ///
  /// **Sin esto dos pruebas no se pueden comparar**, porque no midieron lo
  /// mismo. Un soporte que parece mejor puede ser el que se probó con el motor
  /// en marcha.
  final String? situacion;

  final String? notas;
  final Calidad calidad;

  const PruebaDeSensor({
    required this.t,
    required this.soporte,
    required this.periodoMs,
    required this.calidad,
    this.id,
    this.situacion,
    this.notas,
  });

  /// Cómo se llama el período pedido, para mostrarlo.
  String get comoSePidio => periodoMs <= 0
      ? 'lo más rápido'
      : '$periodoMs ms (${(1000 / periodoMs).round()} Hz pedidos)';
}

class RegistroDePruebas {
  final Base base;

  RegistroDePruebas(this.base);

  int guardar(PruebaDeSensor p) {
    final c = p.calidad;
    base.db.execute(
      'INSERT INTO pruebas_sensor (t, soporte, periodo_ms, muestras, hz, '
      'irregularidad, huecos, saturadas, rms, piso, pico_hz, nitidez, '
      'situacion, notas) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        p.t,
        p.soporte,
        p.periodoMs,
        c.muestras,
        c.hz,
        c.irregularidad,
        c.huecos,
        c.saturadas,
        c.rms,
        c.piso,
        c.picoHz,
        c.nitidez,
        p.situacion,
        p.notas,
      ],
    );
    return base.db.lastInsertRowId;
  }

  /// De la más nueva a la más vieja, que es como se mira una lista de pruebas.
  List<PruebaDeSensor> ultimas([int cuantas = 30]) => base.db
      .select('SELECT * FROM pruebas_sensor ORDER BY t DESC LIMIT ?', [cuantas])
      .map(
        (f) => PruebaDeSensor(
          id: f['id'] as int,
          t: f['t'] as int,
          soporte: f['soporte'] as String,
          periodoMs: f['periodo_ms'] as int,
          situacion: f['situacion'] as String?,
          notas: f['notas'] as String?,
          /* La `Calidad` se rearma desde lo guardado. Los dos percentiles del
             intervalo no se guardan sueltos: lo que se compara es la
             irregularidad, que es lo que se derivaba de ellos. Se ponen de
             modo que el `getter` devuelva exactamente el número guardado. */
          calidad: Calidad(
            muestras: f['muestras'] as int,
            hz: (f['hz'] as num).toDouble(),
            dtMedianaMs: 1,
            dtP95Ms: (f['irregularidad'] as num).toDouble(),
            dtP5Ms: 0,
            huecos: f['huecos'] as int,
            saturadas: f['saturadas'] as int,
            rms: (f['rms'] as num).toDouble(),
            piso: (f['piso'] as num).toDouble(),
            picoHz: (f['pico_hz'] as num).toDouble(),
            picoMagnitud:
                (f['piso'] as num).toDouble() *
                (f['nitidez'] as num).toDouble(),
          ),
        ),
      )
      .toList();

  void borrar(int id) =>
      base.db.execute('DELETE FROM pruebas_sensor WHERE id = ?', [id]);

  /// Las pruebas ordenadas por lo que se quiere comparar, de mejor a peor.
  ///
  /// **Sólo se comparan las que midieron LO MISMO.** Dos soportes probados en
  /// situaciones distintas no se pueden poner uno al lado del otro: el que
  /// parezca mejor puede ser simplemente el que se probó con el motor en
  /// marcha. Es la misma regla que las cubetas de velocidad de la vibración, y
  /// por el mismo motivo.
  List<PruebaDeSensor> compararSoportes(String situacion) {
    final todas = ultimas(100)
        .where((p) => (p.situacion ?? '') == situacion)
        .toList();
    todas.sort((a, b) => b.calidad.nitidez.compareTo(a.calidad.nitidez));
    return todas;
  }

  /// Las situaciones que hay probadas, de la más usada a la menos.
  List<String> situaciones() {
    final cuenta = <String, int>{};
    for (final p in ultimas(100)) {
      final s = p.situacion ?? '';
      if (s.isEmpty) continue;
      cuenta[s] = (cuenta[s] ?? 0) + 1;
    }
    final lista = cuenta.keys.toList();
    lista.sort((a, b) => cuenta[b]!.compareTo(cuenta[a]!));
    return lista;
  }
}
