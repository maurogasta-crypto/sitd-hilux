import 'bitacora.dart';
import 'db/base.dart';

/// La bitácora, en la base, para que sobreviva a cerrar la aplicación.
///
/// **Existe por una falla concreta de `sitd-12`:** el primer reporte real trajo
/// `"bitacora": []`. No estaba rota — vivía en memoria, y el reporte se generó
/// dos horas después del viaje, con la aplicación reabierta en el medio. El
/// único registro de lo que pasó *durante* el viaje, que es exactamente cuando
/// nadie puede mirar la pantalla, se perdía antes de que alguien lo leyera.
///
/// Es el mismo error que ya se había arreglado con los contadores de descarte
/// en `sitd-7`, cometido de nuevo: **un diagnóstico que no sobrevive a cerrar
/// la aplicación no es un diagnóstico.**
class RegistroDeEventos {
  final Base base;

  /// Cuántos eventos se guardan. Pasado ese número se borran los más viejos.
  ///
  /// Mil son varios viajes y unos pocos kilobytes; sin techo, una aplicación
  /// que vive atornillada a una cabina llenaría la tarjeta con su propio
  /// diagnóstico, que es la peor forma de perder los datos que sí importan.
  final int capacidad;

  RegistroDeEventos(this.base, {this.capacidad = 1000});

  /// Cuántos van desde la última poda. Podar en cada escritura sería un DELETE
  /// por segundo para no borrar nada.
  int _desdeLaPoda = 0;

  void guardar(Anotacion a) {
    base.db.execute('INSERT INTO eventos (t, origen, texto) VALUES (?, ?, ?)', [
      a.t,
      nombreDeOrigen(a.origen),
      a.texto,
    ]);
    if (++_desdeLaPoda >= 100) {
      podar();
      _desdeLaPoda = 0;
    }
  }

  void podar() {
    base.db.execute(
      'DELETE FROM eventos WHERE id NOT IN '
      '(SELECT id FROM eventos ORDER BY id DESC LIMIT ?)',
      [capacidad],
    );
  }

  /// Los últimos [cuantos], del más viejo al más nuevo, que es como se leen en
  /// el reporte.
  List<Map<String, dynamic>> ultimos([int cuantos = 400]) {
    final filas = base.db.select(
      'SELECT t, origen, texto FROM eventos ORDER BY id DESC LIMIT ?',
      [cuantos],
    );
    return [
      for (final f in filas.reversed)
        {'t': f['t'] as int, 'origen': f['origen'], 'texto': f['texto']},
    ];
  }

  int get cuantos =>
      base.db.select('SELECT COUNT(*) AS n FROM eventos').first['n'] as int;

  void limpiar() => base.db.execute('DELETE FROM eventos');
}
