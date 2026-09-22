/// Cómo se escribe un número para que lo lea una persona.
///
/// Está separado de las pantallas por la regla del § 11 de
/// `PROTOCOLO-INTERFAZ.md`: un dato se muestra como lo lee una persona, y el
/// formato se arma en un solo lugar. Acá se escribe en español rioplatense —
/// **la coma es el separador decimal**, que es como se lee un tablero en
/// Uruguay.
library;

/// Kilómetros, con una decimal hasta 100 km y sin decimales de ahí en más.
///
/// Por qué cambia: abajo de 100 km la decimal es información —son 100 metros,
/// que en una calibración importan—, y arriba es ruido en la pantalla que se
/// mira de reojo manejando.
String formatearKm(double km) {
  final absoluto = km.abs();
  final texto = absoluto < 100 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
  return '${texto.replaceAll('.', ',')} km';
}

/// Una duración en milisegundos, como la diría alguien: `45 min`, `2 h 07 min`.
///
/// Los segundos sólo aparecen abajo del minuto, que es cuando son lo único que
/// se mueve; después molestan más de lo que informan.
String formatearDuracion(int ms) {
  if (ms < 0) ms = 0;
  final totalSegundos = ms ~/ 1000;
  final horas = totalSegundos ~/ 3600;
  final minutos = (totalSegundos % 3600) ~/ 60;
  final segundos = totalSegundos % 60;
  if (horas > 0) return '$horas h ${minutos.toString().padLeft(2, '0')} min';
  if (minutos > 0) return '$minutos min';
  return '$segundos s';
}

/// Litros, con una decimal: el surtidor corta ahí y el tanque no necesita más.
String formatearLitros(double litros) =>
    '${litros.toStringAsFixed(1).replaceAll('.', ',')} L';

/// Consumo en litros cada 100 km, que es como se habla en Uruguay.
String formatearConsumo(double litrosCada100) =>
    '${litrosCada100.toStringAsFixed(1).replaceAll('.', ',')} L/100 km';

/// Plata, con su moneda adelante y **nunca** sumada con otra.
///
/// Se muestran dos decimales abajo de mil y ninguno arriba: el costo de una
/// carga se lee de un vistazo y los centésimos de un total de cinco mil pesos
/// no le sirven a nadie.
String formatearDinero(double monto, String moneda) {
  final texto = monto.abs() < 1000
      ? monto.toStringAsFixed(2)
      : monto.toStringAsFixed(0);
  return '$moneda ${texto.replaceAll('.', ',')}';
}

/// Una fecha corta, como la diría alguien: `15/09`.
String formatearFecha(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}';
}

/// Una fecha con la hora, como la diría alguien: `21/09 20:27`.
///
/// **Existe porque [formatearFecha] sola no alcanza para una lista de
/// viajes.** Dos viajes del mismo día se verían idénticos, y justamente el
/// caso que hay que poder distinguir es el de la tarde contra el de la noche:
/// el 2026-09-21 hubo cuatro viajes en dos días y tres caían en dos fechas.
/// La hora es lo único que los separa mirando.
///
/// Sin segundos: el que mira esta lista está eligiendo cuál traer, no
/// cronometrando.
String formatearFechaYHora(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)} ${dos(d.hour)}:${dos(d.minute)}';
}

/// La hora con segundos, como la diría alguien: `04:31:07`.
///
/// **Los segundos acá SÍ**, al revés que en [formatearFechaYHora]. Es para
/// sellar una lectura en una observación mientras se mide: lo que se anota es
/// «en este instante el pico saltó», y dos anotaciones del mismo minuto tienen
/// que poder distinguirse. En una lista de viajes serían ruido; acá son el
/// dato.
String formatearHora(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.hour)}:${dos(d.minute)}:${dos(d.second)}';
}
