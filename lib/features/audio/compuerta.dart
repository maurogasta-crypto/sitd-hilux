/// Cuándo el micrófono escucha y cuándo no (`sitd-37`, etapa E).
///
/// Es la regla de fondo que este proyecto escribió en el `CLAUDE.md` desde el
/// primer día: **el micrófono es oportunista, el acelerómetro es el titular**.
/// Se escucha sólo cuando no hay música sonando, no hay una llamada, la
/// camioneta va a más de 30 km/h y estable, y el nivel es razonable. A esa
/// velocidad lo que entra es ruta y motor, no una conversación — y aun así lo
/// único que se guarda son números (ver `regimen.dart`).
///
/// No toca el micrófono ni el sistema: recibe lo que se sabe y decide. Por eso
/// el banco la recorre entera.
library;

/// Por qué una ventana no se usó. `abre` es la única que se guarda.
enum MotivoAudio {
  abre('se escuchó'),
  llamada('hay una llamada'),
  musica('hay audio sonando'),
  sinVelocidad('todavía no hay velocidad del GPS'),
  despacio('a menos de 30 km/h'),
  inestable('la velocidad cambió más de 5 km/h'),
  silencio('el micrófono no entrega nada'),
  saturado('el sonido satura el micrófono');

  final String texto;
  const MotivoAudio(this.texto);
}

/// A partir de qué velocidad se escucha.
const double kmhMinimoParaEscuchar = 30;

/// Cuánto puede cambiar la velocidad entre el principio y el fin de una
/// ventana. Más que esto y las RPM del principio no son las del final.
const double kmhVariacionMaxima = 5;

/// Por debajo de este nivel el micrófono no está entregando (otra app lo
/// tiene tomado, o el sistema lo silenció).
const double nivelMinimoDb = -70;

/// Más de esta fracción de muestras en el techo y el espectro miente.
const double saturacionMaxima = 0.01;

/// Decide si una ventana se usa. Lo que no se sabe cuenta como «no».
MotivoAudio compuerta({
  required bool musica,
  required bool llamada,
  required double? kmh,
  required double? kmhAlEmpezar,
  required double nivelDb,
  required double saturadas,
}) {
  // La llamada primero: si hay una, no importa nada más.
  if (llamada) return MotivoAudio.llamada;
  if (musica) return MotivoAudio.musica;
  if (kmh == null || kmhAlEmpezar == null) return MotivoAudio.sinVelocidad;
  if (kmh < kmhMinimoParaEscuchar || kmhAlEmpezar < kmhMinimoParaEscuchar) {
    return MotivoAudio.despacio;
  }
  if ((kmh - kmhAlEmpezar).abs() > kmhVariacionMaxima) {
    return MotivoAudio.inestable;
  }
  if (nivelDb < nivelMinimoDb) return MotivoAudio.silencio;
  if (saturadas > saturacionMaxima) return MotivoAudio.saturado;
  return MotivoAudio.abre;
}
