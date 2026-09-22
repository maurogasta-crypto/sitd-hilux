/// Esquema de la base local.
///
/// Se escribe en SQL a mano, sin generación de código, a propósito: el
/// proyecto ya carga con un paso de compilación que los otros del ecosistema
/// no tienen, y agregarle `build_runner` significaría que ningún cambio de
/// esquema se puede hacer sin regenerar archivos —algo que no se puede hacer
/// desde un teléfono.
///
/// La concurrencia entre hilos la resuelve SQLite, no Dart: la base se abre en
/// modo WAL, que admite un escritor y varios lectores simultáneos, con
/// `busy_timeout` para que un hilo que llega tarde espere en vez de fallar.
/// Ver `base.dart`.
library;

/// Versión del esquema. Es la que queda escrita en `PRAGMA user_version`.
const int versionEsquema = 6;

/// Cada elemento son las sentencias que llevan el esquema de la versión
/// `índice` a la `índice + 1`. Nunca se edita una migración ya publicada: se
/// agrega otra abajo. Una base en un teléfono no se puede volver a crear.
const List<List<String>> migraciones = [
  // ── 0 → 1 ──────────────────────────────────────────────────────────────
  [
    '''
    CREATE TABLE viajes (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      inicio            INTEGER NOT NULL,
      fin               INTEGER,
      metros            REAL    NOT NULL DEFAULT 0,
      metros_haversine  REAL    NOT NULL DEFAULT 0,
      odo_tablero_ini   REAL,
      odo_tablero_fin   REAL,
      cortes            INTEGER NOT NULL DEFAULT 0,
      notas             TEXT
    )
    ''',
    'CREATE INDEX idx_viajes_inicio ON viajes (inicio DESC)',

    // Las muestras crudas se guardan enteras. Ocupan poco (~30 bytes) y son lo
    // único que no se puede reconstruir: si mañana mejora el filtro, se puede
    // recalcular la distancia de todos los viajes viejos. Un derivado se
    // vuelve a calcular; una muestra perdida, no.
    '''
    CREATE TABLE puntos (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      viaje         INTEGER NOT NULL REFERENCES viajes (id) ON DELETE CASCADE,
      t             INTEGER NOT NULL,
      lat           REAL    NOT NULL,
      lon           REAL    NOT NULL,
      alt           REAL,
      velocidad     REAL    NOT NULL,
      precision_m   REAL    NOT NULL,
      precision_vel REAL
    )
    ''',
    'CREATE INDEX idx_puntos_viaje ON puntos (viaje, t)',

    // El estado de pago, el consumo y la autonomía NO se guardan: se calculan
    // al leer. Acá sólo entra lo que Mauro tecleó en la estación de servicio.
    // Y cada moneda es un sistema aparte: UYU y USD no se suman nunca.
    '''
    CREATE TABLE cargas (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      t            INTEGER NOT NULL,
      litros       REAL    NOT NULL,
      costo        REAL,
      moneda       TEXT    NOT NULL DEFAULT 'UYU',
      odo_tablero  REAL    NOT NULL,
      tanque_lleno INTEGER NOT NULL DEFAULT 1,
      estacion     TEXT,
      notas        TEXT
    )
    ''',
    'CREATE INDEX idx_cargas_t ON cargas (t DESC)',

    '''
    CREATE TABLE ajustes (
      clave TEXT PRIMARY KEY,
      valor TEXT NOT NULL
    )
    ''',
  ],

  // ── 1 → 2 ──────────────────────────────────────────────────────────────
  // La vibración, que entra con la etapa D (`sitd-5`, 16-sep-2026).
  //
  // **Es la primera migración agregada abajo, y muestra para qué está la
  // regla.** La 0 → 1 ya está instalada en un teléfono: editarla no le
  // cambiaría nada a esa base —las migraciones no se vuelven a correr— y en
  // cambio dejaría una instalación nueva distinta de la vieja, con el mismo
  // número de versión. Por eso se agrega abajo y sube `versionEsquema`.
  [
    // NO se guarda la señal cruda del acelerómetro. A 50 Hz por tres ejes son
    // ~2 MB por hora de manejo, y no hace falta: lo que se compara entre
    // viajes es el VECTOR de cada ventana —energía por banda de frecuencia—,
    // que ocupa unos 100 bytes y es lo único que después se puede mirar.
    //
    // `bandas` es texto: las energías separadas por coma. Un BLOB ahorraría
    // la mitad del espacio y costaría poder leer una fila con los ojos, que
    // en un teléfono sin depurador es lo único que hay.
    '''
    CREATE TABLE vibraciones (
      id       INTEGER PRIMARY KEY AUTOINCREMENT,
      viaje    INTEGER NOT NULL REFERENCES viajes (id) ON DELETE CASCADE,
      t        INTEGER NOT NULL,
      cubeta   INTEGER NOT NULL,
      hz       REAL    NOT NULL,
      muestras INTEGER NOT NULL,
      rms      REAL    NOT NULL,
      pico     REAL    NOT NULL,
      bandas   TEXT    NOT NULL
    )
    ''',
    // Por cubeta primero: la comparación SIEMPRE es contra el histórico de la
    // misma cubeta de velocidad, nunca contra todo junto.
    'CREATE INDEX idx_vibraciones_cubeta ON vibraciones (cubeta, t)',
    'CREATE INDEX idx_vibraciones_viaje ON vibraciones (viaje)',
  ],

  // ── 2 → 3 ──────────────────────────────────────────────────────────────
  // El diagnóstico del viaje, que hasta ahora vivía sólo en la pantalla y se
  // perdía al cerrarlo (`sitd-7`, 16-sep-2026).
  //
  // **Es lo que faltaba para que un viaje se pueda diagnosticar DESPUÉS.** Un
  // viaje que no registró nada no guardaba ni un punto, así que en la base
  // quedaba una fila vacía y ninguna explicación: exactamente el caso de los
  // siete minutos en cero. Ahora el porqué queda escrito al lado del viaje, y
  // viaja en el reporte.
  [
    'ALTER TABLE viajes ADD COLUMN descartadas INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE viajes ADD COLUMN sin_doppler INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE viajes ADD COLUMN precision_descartada REAL',
    // Los motivos como texto, `motivo=cantidad` separados por coma. Una tabla
    // aparte para cinco números por viaje sería más prolija y menos legible: en
    // un teléfono sin depurador, poder leer una fila con los ojos gana.
    'ALTER TABLE viajes ADD COLUMN motivos TEXT',
  ],

  // ── 3 → 4 ──────────────────────────────────────────────────────────────
  // La bitácora del intercambio con el sistema, que hasta `sitd-12` vivía
  // sólo en memoria (17-sep-2026).
  //
  // **Entró porque el primer reporte real la trajo vacía.** No era un error de
  // la bitácora: era que vive en memoria y el reporte se generó dos horas
  // después del viaje, con la aplicación reabierta en el medio. O sea que el
  // único registro de lo que pasó durante el viaje —que es justo cuando nadie
  // puede mirar la pantalla— se perdía antes de que alguien pudiera leerlo.
  //
  // Es el mismo razonamiento que la migración de arriba y el mismo error
  // cometido dos veces: un diagnóstico que no sobrevive a cerrar la aplicación
  // no es un diagnóstico.
  [
    '''
    CREATE TABLE eventos (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      t       INTEGER NOT NULL,
      origen  TEXT    NOT NULL,
      texto   TEXT    NOT NULL
    )
    ''',
    'CREATE INDEX idx_eventos_t ON eventos (t DESC)',
  ],

  // ── 4 → 5 ──────────────────────────────────────────────────────────────
  // La cola de viajes que faltan subir (19-sep-2026, etapa G).
  //
  // **Es una COLA y no un intento al vuelo**, y ése es el punto entero: la
  // camioneta anda por lugares sin señal, y un viaje que termina lejos de una
  // antena no puede perderse por eso. Se encola al terminar y se reintenta
  // cuando haya red — al abrir la aplicación o cuando alguien toque el botón.
  //
  // Y **la subida nunca frena la medición**: si esta tabla no existiera, o si
  // la red no contestara nunca, la aplicación sigue midiendo exactamente
  // igual. Eso es lo que no se puede perder al agregar una nube.
  [
    '''
    CREATE TABLE subidas (
      viaje       INTEGER PRIMARY KEY REFERENCES viajes (id) ON DELETE CASCADE,
      encolado    INTEGER NOT NULL,
      subido      INTEGER,
      intentos    INTEGER NOT NULL DEFAULT 0,
      ultimoError TEXT
    )
    ''',
    'CREATE INDEX idx_subidas_pendientes ON subidas (subido, encolado)',
  ],

  // ── 5 → 6 ──────────────────────────────────────────────────────────────
  // Las pruebas del propio sensor (22-sep-2026).
  //
  // **Guardarlas es la mitad de la herramienta, no un extra.** Lo que Mauro
  // quiere saber es si conviene el tablero o la palanca de cambios, y eso no
  // es un número sino una COMPARACIÓN. Una pantalla en vivo sola no alcanza:
  // uno mira la primera, se baja, ata el teléfono en otro lado, mira la
  // segunda, y para entonces ya no se acuerda de la primera. Con esto queda
  // la lista, y la comparación se hace mirando.
  //
  // No lleva la señal cruda: lo que se guarda son los números que salen de
  // `medirCalidad`, que es lo que se compara. Es el mismo criterio que las
  // ventanas de vibración — el vector se guarda, el audio no.
  [
    '''
    CREATE TABLE pruebas_sensor (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      t             INTEGER NOT NULL,
      -- Dónde estaba el teléfono. Es texto libre a propósito: los soportes
      -- que se le ocurran a Mauro no los puede enumerar este archivo.
      soporte       TEXT    NOT NULL,
      -- El período que se PIDIÓ, en milisegundos. Cero es «lo más rápido que
      -- puedas». Se guarda porque la frecuencia que se midió no lo dice: el
      -- sistema entrega lo que quiere.
      periodo_ms    INTEGER NOT NULL,
      muestras      INTEGER NOT NULL,
      hz            REAL    NOT NULL,
      irregularidad REAL    NOT NULL,
      huecos        INTEGER NOT NULL,
      saturadas     INTEGER NOT NULL,
      rms           REAL    NOT NULL,
      piso          REAL    NOT NULL,
      pico_hz       REAL    NOT NULL,
      nitidez       REAL    NOT NULL,
      -- Qué estaba pasando: motor apagado, ralentí, andando a 80. Sin esto
      -- dos pruebas no se pueden comparar, porque no midieron lo mismo.
      situacion     TEXT,
      notas         TEXT
    )
    ''',
    'CREATE INDEX idx_pruebas_sensor_t ON pruebas_sensor (t DESC)',
  ],
];

/// Comprobaciones del esquema que no dependen de que haya un SQLite cargado,
/// para que el banco de pruebas corra en cualquier lado.
///
/// Devuelve la lista de problemas encontrados; vacía significa que está bien.
List<String> revisarEsquema() {
  final problemas = <String>[];

  if (migraciones.length != versionEsquema) {
    problemas.add(
      'versionEsquema es $versionEsquema pero hay ${migraciones.length} '
      'migraciones: cada versión nueva tiene que traer la suya',
    );
  }

  for (var i = 0; i < migraciones.length; i++) {
    if (migraciones[i].isEmpty) {
      problemas.add('la migración $i → ${i + 1} está vacía');
    }
    for (final sql in migraciones[i]) {
      if (sql.trim().isEmpty) {
        problemas.add('la migración $i → ${i + 1} tiene una sentencia vacía');
      }
    }
  }

  // Toda tabla creada tiene que tener su índice, salvo las de clave única.
  final sinIndice = <String>{'ajustes'};
  final creadas = <String>{};
  final indexadas = <String>{};
  final reTabla = RegExp(r'CREATE TABLE\s+(\w+)', caseSensitive: false);
  final reIndice = RegExp(
    r'CREATE INDEX\s+\w+\s+ON\s+(\w+)',
    caseSensitive: false,
  );

  for (final paso in migraciones) {
    for (final sql in paso) {
      final t = reTabla.firstMatch(sql);
      if (t != null) creadas.add(t.group(1)!);
      final x = reIndice.firstMatch(sql);
      if (x != null) indexadas.add(x.group(1)!);
    }
  }

  for (final tabla in creadas) {
    if (!indexadas.contains(tabla) && !sinIndice.contains(tabla)) {
      problemas.add(
        'la tabla "$tabla" no tiene índice y no está en la lista de las que '
        'no lo necesitan',
      );
    }
  }

  return problemas;
}
