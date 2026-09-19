import '../../core/bitacora.dart';
import '../../core/db/base.dart';

/// Un viaje esperando subir.
class Pendiente {
  final int viaje;
  final int encolado;
  final int intentos;
  final String? ultimoError;

  const Pendiente({
    required this.viaje,
    required this.encolado,
    required this.intentos,
    this.ultimoError,
  });
}

/// La cola de viajes que faltan subir.
///
/// **Existe porque la camioneta anda por lugares sin señal.** Un viaje que
/// termina lejos de una antena no puede perderse por eso: se encola al
/// terminar y se reintenta cuando haya red — al abrir la aplicación, o cuando
/// alguien toque el botón.
///
/// **Y la cola nunca frena la medición.** Si la red no contesta nunca, esto
/// junta filas y la aplicación sigue midiendo exactamente igual que antes de
/// que existiera una nube. Es la propiedad que no se puede perder.
class ColaDeSubida {
  final Base base;

  /// El reloj, inyectable para el banco.
  final int Function() ahora;

  ColaDeSubida(this.base, {int Function()? reloj})
    : ahora = reloj ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Pone un viaje en la cola. Repetir no duplica: la clave es el viaje.
  void encolar(int viaje) {
    base.db.execute(
      'INSERT INTO subidas (viaje, encolado, intentos) VALUES (?, ?, 0) '
      'ON CONFLICT (viaje) DO NOTHING',
      [viaje, ahora()],
    );
  }

  /// Los que faltan, del más viejo al más nuevo. **El más viejo primero** a
  /// propósito: si algo se va a perder por falta de espacio o de paciencia,
  /// que no sea lo que más esperó.
  List<Pendiente> pendientes([int cuantos = 20]) => base.db
      .select(
        'SELECT viaje, encolado, intentos, ultimoError FROM subidas '
        'WHERE subido IS NULL ORDER BY encolado LIMIT ?',
        [cuantos],
      )
      .map(
        (f) => Pendiente(
          viaje: f['viaje'] as int,
          encolado: f['encolado'] as int,
          intentos: f['intentos'] as int,
          ultimoError: f['ultimoError'] as String?,
        ),
      )
      .toList();

  int get cuantosFaltan =>
      base.db
              .select('SELECT COUNT(*) AS n FROM subidas WHERE subido IS NULL')
              .first['n']
          as int;

  int get cuantosSubidos =>
      base.db
              .select(
                'SELECT COUNT(*) AS n FROM subidas WHERE subido IS NOT NULL',
              )
              .first['n']
          as int;

  void marcarSubido(int viaje) {
    base.db.execute(
      'UPDATE subidas SET subido = ?, ultimoError = NULL WHERE viaje = ?',
      [ahora(), viaje],
    );
  }

  /// Anota que falló, **sin sacarlo de la cola**. Un viaje sólo sale cuando
  /// subió: que la red falle veinte veces no es motivo para perderlo.
  void marcarFalla(int viaje, String error) {
    base.db.execute(
      'UPDATE subidas SET intentos = intentos + 1, ultimoError = ? '
      'WHERE viaje = ?',
      [error, viaje],
    );
  }

  bool estaSubido(int viaje) =>
      base.db
          .select('SELECT subido FROM subidas WHERE viaje = ?', [viaje])
          .map((f) => f['subido'])
          .firstOrNull !=
      null;

  /// Cuántos viajes ya subidos se recuerdan antes de podar. Las filas son
  /// diminutas, pero sin techo una aplicación atornillada a una cabina junta
  /// filas para siempre — la misma lección que la bitácora.
  static const int recordarSubidos = 500;

  void podar() {
    base.db.execute(
      'DELETE FROM subidas WHERE subido IS NOT NULL AND viaje NOT IN '
      '(SELECT viaje FROM subidas WHERE subido IS NOT NULL '
      'ORDER BY subido DESC LIMIT ?)',
      [recordarSubidos],
    );
  }
}

/// Anota en la bitácora que un viaje entró a la cola. Separado para que la
/// cola siga siendo pura base de datos y se pueda probar sin nada más.
void anotarEncolado(int viaje) => bitacora.anotar(
  Origen.sistema,
  'Viaje $viaje encolado para subir. Si no hay señal, espera.',
);
