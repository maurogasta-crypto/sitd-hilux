/// La geometría de la rueda, en UN solo lugar.
///
/// ## Por qué existe este archivo
///
/// Porque el número estaba escrito a mano en cuatro comentarios y tres de
/// ellos decían cosas distintas. La auditoría del 2026-09-22 encontró que
/// `espectro.dart` y `ventana.dart` afirmaban «un desbalanceo a 60 km/h está
/// alrededor de 8 Hz y a 110 alrededor de 15», y la cuenta con la rueda REAL
/// de esta camioneta da **6,98 y 12,80** — un 15 y un 17 % de más. No era un
/// error de tipeo: esos comentarios se escribieron con una cubierta genérica,
/// antes de que Mauro midiera la suya, y cuando el `CLAUDE.md` se corrigió con
/// el número medido nadie volvió a esos dos archivos.
///
/// Un número repetido en cuatro lugares diverge. Es el mismo error que este
/// ecosistema ya pagó con los sellos de versión y con el texto de las reglas.
///
/// ## Y esto NO se usa para medir distancia
///
/// **Es la regla de fondo del proyecto y conviene tenerla acá al lado**, donde
/// está la tentación. El GPS ya mide la distancia real: no sabe ni le importa
/// qué rueda está puesta. El que miente es el odómetro del tablero, y el
/// factor que lo traduce **se aprende de los viajes**, nunca se calcula de la
/// medida de la cubierta.
///
/// Para lo que sirve el diámetro es para **leer un espectro**: decir en qué
/// frecuencia habría que buscar un desbalanceo a tal velocidad. Si algún día
/// alguien usa esto para convertir vueltas de rueda en kilómetros, eso es el
/// error, no la solución.
library;

import 'dart:math' as math;

/// Diámetro de la rueda **bajo carga**, en metros. Lo midió Mauro el
/// 2026-09-19.
///
/// **Bajo carga y no libre, y la diferencia es el 5,3 %.** La cubierta es una
/// 265/70R17, que sin peso encima da 80,3 cm; con la camioneta arriba se
/// achata a 76. Ese achatamiento es exactamente el motivo por el que el factor
/// de neumáticos se aprende de los viajes en vez de calcularse — un número de
/// catálogo habría dado 5 % de más, que es más grande que el efecto que se
/// busca medir.
const double diametroBajoCarga = 0.76;

/// Lo que avanza la camioneta por cada vuelta de rueda, en metros.
const double circunferencia = math.pi * diametroBajoCarga;

/// Cuántas vueltas por segundo da la rueda a [kmh]. Es el **orden 1**: la
/// frecuencia donde aparece un desbalanceo.
///
/// ```
/// 20 km/h ->  2,33 Hz      80 km/h ->  9,31 Hz
/// 60 km/h ->  6,98 Hz     110 km/h -> 12,80 Hz
/// ```
double frecuenciaDeRueda(double kmh) => (kmh / 3.6) / circunferencia;

/// La cuenta al revés: a qué velocidad la rueda gira a [hz].
///
/// Sirve para decir «arriba de tantos km/h esto se sale del espectro», que es
/// la forma en que un techo de frecuencia se vuelve accionable para alguien
/// que mira un velocímetro y no un analizador.
double velocidadParaFrecuencia(double hz) => hz * 3.6 * circunferencia;

/// Relación del diferencial: cuántas vueltas da el cardán por cada vuelta de
/// rueda.
///
/// **Es un valor de catálogo y no está medido**, y por eso se llama
/// «aproximada». Las Hilux 3.0 de esos años traen 3,583 o 3,909 según la
/// versión, y de cuál es ésta no hay forma de enterarse desde el teléfono. Con
/// cualquiera de los dos la conclusión que importa no cambia: **el cardán se
/// sale del espectro arriba de unos 60 km/h**, y de la banda de 17 Hz arriba
/// de unos 40.
///
/// El día que haya tacómetro esto se puede MEDIR en vez de suponer: la
/// relación total en directa ES la del diferencial.
const double relacionDiferencialAproximada = 3.583;

/// La velocidad más alta a la que un componente que gira [orden] veces por
/// vuelta de rueda todavía entra en un espectro con este [nyquist].
///
/// Es la cuenta que convierte «Nyquist 24,93 Hz» —que no le dice nada a
/// nadie— en «arriba de 60 km/h el cardán ya no se ve».
double velocidadMaximaVisible(double nyquist, double orden) =>
    velocidadParaFrecuencia(nyquist / orden);
