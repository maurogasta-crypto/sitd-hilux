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
