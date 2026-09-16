/// Sellos de versión, a la vista en la pantalla.
///
/// Misma disciplina que el resto del ecosistema: si se cambia un archivo con
/// lógica, sube su sello. Acá además sirve para saber qué APK quedó instalado
/// en el teléfono de la cabina, que es un aparato al que no se le pregunta
/// fácil.
library;

/// Sello de la aplicación entera. Sube en cada tanda.
const String selloApp = 'sitd-5';

/// Etapa del proyecto, tal como la definió el plan: 1 es desarrollo sobre el
/// Redmi 15, 2 es producción sobre el Redmi Note 9 montado en la cabina.
const int etapa = 1;
