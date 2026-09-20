# SITD-Hilux

Telemetría, odometría y diagnóstico mecánico para una **Toyota Hilux 3.0**
(1KD-FTV, 2008-2011). Android, sin conexión, sin servidor, sin cuenta de nadie.

> **Estado: tanda 10 — el reloj del GPS.** Ya mide. Se abre un viaje, el GPS
> entrega una muestra por segundo, la distancia se integra de la velocidad
> Doppler y cada muestra cruda queda guardada en el teléfono. Lleva las cargas
> de combustible, con el consumo y el factor de neumáticos calculados al leer.
> Y desde la tanda 5 escucha el acelerómetro: aprende cómo vibra esta
> camioneta a cada velocidad y avisa cuando algo cambia. Y tiene un panel de
> sensores que dice, en vivo, qué ve el teléfono y en qué estado está cada
> sensor. Y desde la tanda 7 los datos pueden salir del teléfono: un reporte
> para arreglar cosas y un respaldo completo. Lo que falta es el micrófono.

## Instalar en el teléfono

Desde el navegador del teléfono, no desde la aplicación de GitHub:

1. Entrar a
   [releases/tag/ultimo](https://github.com/maurogasta-crypto/sitd-hilux/releases/tag/ultimo)
   y tocar `sitd-hilux.apk`, que es el único archivo que hay.
2. Al abrir lo descargado, Android dice que no puede instalar apps desconocidas
   de esa fuente. En ese mismo cartel: **Ajustes → Permitir desde esta fuente →
   Atrás**. Es una sola vez.
3. **En Xiaomi hay dos pasos más**, y los dos asustan sin motivo: aparece
   «Analizando la app…» y después un cartel de que no es de confianza →
   **Instalar de todos modos**. Si insiste, en **Seguridad → Ajustes → Analizar
   apps antes de instalar** se apaga mientras se instala.

Desconfía porque el APK está firmado con la clave de depuración, no con una de
Play Store. Es la nuestra: la compila el workflow de este repositorio.

**En el release hay un solo archivo y siempre se llama igual: `sitd-hilux.apk`.**
Hasta la corrida 13 había dos —ése y `sitd-hilux-NN.apk`— que eran el mismo
archivo byte por byte, y lo único que lograban era que al abrir la página
hubiera que elegir entre dos cosas idénticas. El rastro de cada tanda existe
igual y está donde corresponde: el *artifact* numerado de cada corrida, en la
pestaña **Actions**.

El título del release dice el **sello** seguido del número de corrida —
`sitd-11 · corrida 16`, por ejemplo—, y ese sello es el mismo que muestra la
aplicación en «Estado»: si los dos coinciden, lo instalado es lo publicado. El
número de acá es un ejemplo y no se mantiene a mano: el que vale es el del
release.

> **Enlace directo, para guardar:**
> `https://github.com/maurogasta-crypto/sitd-hilux/releases/download/ultimo/sitd-hilux.apk`

### La firma: por qué hoy hay que desinstalar, y cómo se arregla

**Si la instalación falla diciendo «conflicto con un paquete», no es el
teléfono: pasa siempre, con todas las tandas.** El APK se firma con la clave de
depuración que genera Gradle, y **en un runner de GitHub esa clave se genera
nueva en cada corrida**. Dos APK de dos tandas distintas llevan firmas
distintas, y Android no deja actualizar una aplicación con una firma que no es
la que tenía.

Está comprobado, no deducido: el certificado del APK de la corrida 8 dice
`notBefore = 16-sep-2026 03:58:33 GMT`, el minuto exacto de esa compilación.

**Mientras no haya clave propia**, actualizar es desinstalar y volver a
instalar, y **eso borra la base**. Antes conviene sacar un respaldo: menú de los
tres puntos → Sacar los datos → Respaldo completo. (Todavía no se puede volver a
meterlo: sirve para no perder la historia, no para restaurarla en el teléfono.)

**La solución es una clave propia en GitHub Secrets**, y el workflow ya la usa
si está —sigue compilando con la de depuración si no, avisando en las notas del
release cuál usó—. Lo que falta es generarla, y para eso hace falta `keytool`.

> **Y esto se puede hacer DESDE EL TELÉFONO.** Hasta el 2026-09-20 acá decía que
> `keytool` «no está en un teléfono» y que había que esperar una computadora.
> Era falso: `keytool` viene con cualquier JDK, y en Android hay JDK — **Termux**.
> Sobre esa premisa equivocada se decidió el 2026-09-16 seguir desinstalando en
> cada tanda, y eso costó cuatro días de base borrada en cada actualización.

En **Termux**, una sola vez:

```bash
pkg install openjdk-17

keytool -genkeypair -v \
  -keystore sitd-hilux.jks -storetype JKS \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias sitd -dname "CN=SITD Hilux, O=SITD, C=UY"

base64 -w0 sitd-hilux.jks > sitd-hilux.jks.b64
```

Pide una contraseña dos veces: es la que va en `FIRMA_STORE_PASS` y
`FIRMA_KEY_PASS`. En una computadora es el mismo comando, sin el `pkg install`
(y en Mac, `base64 -i … -o …`).

**Lo que se gana no es sólo dejar de desinstalar.** Si la instalación no borra
la base, **la configuración de la nube tampoco se pierde**: vive en `ajustes`
del mismo SQLite. Hoy hay que volver a pegarla en cada tanda, y con la clave
propia se pega **una sola vez**. Son el mismo problema y se arreglan juntos.

**Y por eso la credencial no va adentro del APK**, aunque parezca el atajo: el
APK se baja sin cuenta de un repositorio público, así que una contraseña adentro
sería un dato público. Que la aplicación «la lea de algún lado» tiene el mismo
agujero — cualquier lugar del que pueda leerla sin credenciales es un lugar del
que puede leerla cualquiera.

Después, en **Settings → Secrets and variables → Actions → New repository
secret**, cuatro veces:

| Secreto | Qué se pega |
|---|---|
| `FIRMA_JKS` | el contenido de `sitd-hilux.jks.b64`, todo de una línea |
| `FIRMA_STORE_PASS` | la contraseña del keystore |
| `FIRMA_KEY_PASS` | la de la clave (puede ser la misma) |
| `FIRMA_ALIAS` | `sitd` |

Y dos advertencias que valen más que el procedimiento:

1. **El archivo `.jks` hay que guardarlo.** Si se pierde, no hay forma de
   volver a firmar una actualización: habría que desinstalar y empezar de cero,
   para siempre. Va al gestor de contraseñas o a un lugar que sobreviva a que
   se rompa la computadora — y **no al repositorio**, que es público.
2. **Ni el archivo ni las contraseñas se pegan en un chat.** Los carga Mauro a
   mano en la web de GitHub. El entregable de un chat es el nombre exacto de
   cada variable y dónde va, que es lo que está en esta tabla.

## Cómo se actualiza

Es siempre lo mismo y conviene tenerlo claro, porque va a pasar en cada tanda:

1. El cambio se empuja a `main`.
2. GitHub Actions corre la verificación previa —analizador, formato, banco de
   pruebas—, compila el APK y **reemplaza el release `ultimo`**. Tarda unos
   cinco minutos. Si algo de la verificación falla, no se publica nada: el
   release sigue siendo el anterior.
3. Se entra al enlace de siempre, se baja el `.apk` y **se instala encima del
   que está**. No se desinstala nada: es la misma clave de firma, así que
   Android lo toma como una actualización.

**Los datos no se tocan.** La base vive en el almacenamiento privado de la
aplicación (`/data/user/0/uy.gasta.sitd_hilux/app_flutter/sitd.db`) y sobrevive
a la actualización: los viajes, los puntos y las cargas siguen ahí. Lo único
que los borra es **desinstalar** la aplicación o darle «Borrar datos» a mano.

**Si una tanda cambia el esquema de la base**, la migración corre sola al abrir
y `PRAGMA user_version` sube. Una migración publicada no se edita nunca: se
agrega otra abajo. Por eso una base vieja siempre sabe llegar a la nueva, y por
eso nunca hace falta empezar de cero.

**Cómo saber qué versión tenés puesta:** el sello, arriba a la derecha en
«Estado» (`sitd-4`, `sitd-5`…). Es lo que hay que mirar antes de reportar algo
raro, porque dice exactamente qué código está corriendo en ese teléfono.

**Lo que NO hay es actualización automática.** Android no la hace para un APK
instalado de costado, así que cada tanda se instala a mano. Es el precio de no
pasar por Play Store, y hoy conviene: publicar ahí obliga a una clave propia, a
una ficha de privacidad y a una revisión por cada cambio.

## Cómo se usa

Una pantalla, tres botones y ningún menú:

| | |
|---|---|
| **Empezar el viaje** | pide el permiso de ubicación —la primera vez— y abre un viaje |
| **Pausar** | suelta el GPS sin cerrar el viaje. Para una parada larga |
| **Terminar** | cierra el viaje y deja el total escrito |
| **Pantalla encendida** | interruptor: mientras el viaje mide, la pantalla no se apaga sola |

El menú de los tres puntos lleva también a **Sacar los datos**, que son dos
cosas distintas y conviene no confundirlas:

| | Qué lleva | A dónde va |
|---|---|---|
| **Reporte para desarrollo** | kilómetros, contadores, por qué se descartó cada muestra, resumen de velocidades y precisiones, vectores de vibración y cargas. **Ni una coordenada** | por donde sea: chat, mail, lo que haya |
| **Respaldo completo** | una copia de la base tal cual está | Drive, una computadora, una tarjeta. **A un chat no**: lleva el recorrido |

El reporte es lo que hay que mandar cuando algo no anda: trae todo lo que hace
falta para entender qué pasó sin traer dónde estuvo la camioneta. Hay una
prueba en el banco que busca coordenadas en el texto entero del archivo, así
que eso no depende de que alguien se acuerde.

El menú de los tres puntos lleva a **Sensores**: qué está entregando cada
sensor del teléfono ahora mismo, a qué frecuencia real, y —para el GPS— por
qué se descarta lo que se descarta. **Es la primera pantalla que hay que abrir
cuando un viaje no registra kilómetros**: dice si el receptor está callado, si
llega sin velocidad, o si llegan posiciones con tanto error que no pasan el
filtro.

El icono de las ondas lleva a **Vibración**: lo que la aplicación fue
aprendiendo de cómo vibra la camioneta a cada velocidad, y los avisos si algo
cambió. No hay nada que tocar ahí — se mide sola mientras el viaje anda.

El icono del surtidor, arriba, lleva a **Combustible**: ahí se anota cada
carga —litros, odómetro del tablero, costo, si quedó lleno— y se ven el
consumo, el costo por kilómetro y el factor de neumáticos. Nada de eso se
guarda calculado: sale de las cargas cada vez que se abre la pantalla.

Arriba, los kilómetros en grande y la velocidad. Abajo, lo que hay que mirar
cuando algo no cuadra: muestras usadas, descartadas, **sin velocidad**, cortes,
el haversine de control y la discrepancia entre los dos métodos. El icono de
información de la barra lleva al estado de la aplicación y a los últimos
viajes.

### Si el GPS no entrega ni una posición: los tres modos

**El caso que los trajo:** dos veces, a cielo abierto, el receptor no entregó
**ni una** lectura. Ni siquiera descartadas — cero. Con cero, el problema está
**antes** del filtro: o del permiso, o de cómo se le pide al sistema.

En **Sensores**, cuando no hay un viaje midiendo, la tarjeta del GPS muestra
tres cosas que se saben *antes* de la primera posición:

- **el permiso con su nombre** (`whileInUse`, `denied`, `deniedForever`…),
- si la **ubicación del sistema** está encendida,
- y si **el sistema tiene una última posición conocida**. Ésta es la que separa
  dos mundos: si la hay, el receptor del teléfono funciona y el problema es de
  cómo la pide esta aplicación; si no hay ninguna, el receptor no fijó nunca y
  eso no lo arregla ningún código.

Y abajo, un selector con tres formas de pedirlas:

| Modo | Qué saca del medio |
|---|---|
| **Normal** | como mide un viaje: servicio en primer plano con notificación, proveedor de Google |
| **Sin notificación** | saca el servicio en primer plano. Si con esto entran y con «Normal» no, **el que falla es el servicio** — y HyperOS los bloquea con la mano suelta |
| **Receptor directo** | usa el `LocationManager` de Android en vez del proveedor de Google: saltea Play Services entero |

Se prueba parado en la calle: se elige un modo, se esperan un par de minutos y
se mira el contador. El que entregue dice cuál era el problema.

**Y la tarjeta dice hace cuánto que espera, y en qué paso está.** «Esperando» a
los tres segundos y «Esperando» a los tres minutos son cosas muy distintas y sin
el reloj se leen igual. Los pasos son tres: preguntando el permiso, suscripto y
esperando que el receptor entregue, o no se pudo arrancar. La gracia del GPS es
de minuto y medio —no los cuatro segundos de los otros sensores— porque un
receptor frío tarda entre treinta segundos y un minuto en fijar satélites, y
acusarlo antes de eso enseña a no mirar el aviso.

### Y desde `sitd-11` no hace falta probarlos a mano: un viaje los prueba solo

Probar los tres modos en la calle sirve, pero exige que alguien esté parado
mirando el teléfono — y quien está arriba de la camioneta está manejando. Así
que **un viaje ahora los recorre solo**:

1. arranca en **Normal**, que es el modo bueno;
2. si a los **90 segundos** no llegó **ni una** posición, baja a **Sin
   notificación**;
3. si a los 45 más sigue sin llegar nada, baja a **Receptor directo**, y ahí se
   queda.

Cuenta **hasta la primera lectura y nada más**: apenas el receptor habla, la
cascada se queda quieta. Una posición que llega sin velocidad Doppler también
cuenta — no sirve para medir, pero prueba que el receptor está hablando, que es
lo que la cascada quiere saber.

Los 90 segundos del primer escalón son a propósito: un receptor frío tarda entre
treinta segundos y un minuto en fijar satélites, y bajar antes sería abandonar
por impaciencia el único modo que sigue midiendo con la pantalla apagada. Los
otros dos miden **menos**, y esa pérdida está aceptada: medir de menos es
infinitamente más que no medir.

**La pantalla del viaje dice en qué modo quedó.** Si dice «Normal», la cascada
nunca hizo falta. Si dice otra cosa, ese cartel es la respuesta a la pregunta
que tres salidas a la calle no contestaron — y conviene contarla.

### El permiso de notificaciones, que hasta `sitd-10` estaba declarado y nunca se pedía

Desde Android 13 la notificación del servicio en primer plano necesita
`POST_NOTIFICATIONS` para **verse**. Estaba declarado en el manifiesto desde
`sitd-9`, y declararlo sin pedirlo en tiempo de ejecución no hace absolutamente
nada: el permiso quedaba negado y el servicio, sin cartel.

Un servicio en primer plano invisible es justo lo que un Xiaomi mata sin que
nadie se entere, así que desde `sitd-11` se pide —una vez por viaje, no una por
modo—. Si sale negado **no se impide medir**: eso sería cambiar un problema de
visibilidad por uno de odometría. Queda escrito en la pantalla del viaje y en la
de sensores, con dónde se da.

### Lo que el panel de sensores encontró en el Redmi 15

Medido el 2026-09-16, no deducido de una ficha técnica: el acelerómetro entrega
**72,3 Hz** —más de los 50 que se asumían— y el magnetómetro 5 Hz, pero el
**giróscopo, la aceleración lineal y el barómetro no contestan**. Un teléfono de
gama de entrada sin giróscopo es normal, y sin giróscopo Android tampoco ofrece
la aceleración lineal: las dos ausencias son la misma.

No rompe nada —ninguna etapa depende del giróscopo y el acelerómetro crudo es el
titular— pero queda dicho: lo que dependa del giróscopo no se puede desarrollar
en este teléfono.

### Las dos cosas que hay que hacer a mano en el teléfono

**Permiso de ubicación: «Mientras se usa la aplicación» alcanza.** No se pide
«Permitir todo el tiempo», a propósito: con un servicio en primer plano de tipo
`location` no hace falta, y es el diálogo más invasivo que tiene Android.

**MIUI/HyperOS mata los servicios en segundo plano.** A mano: Ajustes →
Aplicaciones → SITD Hilux → **Autostart encendido**, y **Ahorro de batería →
Sin restricciones**. Sin eso el GPS se apaga con la pantalla y no avisa. Es
configuración **del aparato**, no del código, así que se repite en cada
teléfono donde se instale — hoy el Redmi 15, y el Redmi Note 9 de la cabina
cuando esté a mano.

**Y si aun así el sistema mata la aplicación en medio de un viaje, no se pierde
nada:** cada muestra se guardó apenas llegó, y al volver a abrir el viaje se
retoma con sus kilómetros. Está probado en el banco (`servicio_test.dart`).

## Mapa de archivos

```
lib/
├── core/
│   ├── db/
│   │   ├── esquema.dart     SQL y migraciones. Una migración publicada
│   │   │                    NO se edita: se agrega otra abajo.
│   │   └── base.dart        Apertura, WAL, migración, ajustes.
│   ├── arranque.dart        Lo que se arma una vez al abrir: base,
│   │                        registro, servicio. No pide permisos.
│   ├── bitacora.dart        Lo que la app le pidió al sistema y lo que el
│   │                        sistema contestó. Sin una sola coordenada.
│   ├── registro_eventos.dart  Esa bitácora EN DISCO, para que sobreviva a
│   │                        cerrar la aplicación — que es cuando se pierde.
│   └── version.dart         Sellos, a la vista en «Estado».
├── features/
│   └── odometro/
│       ├── muestra.dart     La lectura del GPS y el par de calibración.
│       ├── integrador.dart  Distancia por velocidad Doppler: `integrar`
│       │                    para una lista y `Acumulador` para el vivo.
│       ├── factor.dart      Corrección del odómetro de fábrica.
│       ├── fuente.dart      La interfaz del GPS, y por qué es una interfaz.
│       ├── fuente_gps.dart  El GPS real, y las tres formas de pedírselo.
│       ├── cascada.dart     Prueba esas tres formas solo, hasta que una
│       │                    entregue, y dice cuál quedó puesta.
│       ├── modo_recordado.dart  Cuál entregó la última vez, para no volver
│       │                    a perder noventa segundos descubriéndolo.
│       ├── registro.dart    Viajes, puntos y los pares de calibración.
│       └── servicio.dart    Junta las tres piezas y sostiene el viaje.
│   ├── combustible/
│   │   ├── carga.dart       Una carga, tal como se teclea en la estación.
│   │   ├── consumo.dart     Consumo de lleno a lleno, calculado al leer.
│   │   └── registro_cargas.dart  Cargas y el ajuste del tanque.
│   ├── respaldo/
│   │   └── reporte.dart     Qué sale del teléfono, y qué no.
│   ├── nube/
│   │   ├── credencial.dart  Los cuatro datos que Mauro pega a mano. NO
│   │   │                    están en el repositorio ni en el APK.
│   │   ├── cola.dart        Los viajes que faltan subir. Sin señal esperan.
│   │   ├── recorte.dart     Que el documento entre en el límite de 1 MB,
│   │   │                    sacando primero lo que se puede reconstruir.
│   │   ├── subida.dart      Firestore por REST. Sin SDK: el SDK pediría un
│   │   │                    google-services.json en un repo público.
│   │   └── servicio_nube.dart  Junta las tres, y clava el alcance.
│   ├── permisos/
│   │   └── avisos.dart      El permiso de notificaciones, que hace VISIBLE
│   │                        la notificación del servicio en primer plano.
│   ├── sensores/
│   │   ├── sensores.dart    Estado de un sensor y frecuencia medida.
│   │   └── satelites.dart   Lo que ve la ANTENA: cuántos satélites y con
│   │                        cuánta señal, antes de que haya una posición.
│   └── vibracion/
│       ├── espectro.dart    FFT propia, ventana de Hann y energía por banda.
│       ├── ventana.dart     Las cubetas de velocidad y el vector que se guarda.
│       ├── analisis.dart    Línea base robusta, desvíos e histéresis.
│       ├── cobertura.dart   Cuánto aprendió de cada velocidad y cuánto
│       │                    falta, en tiempo. Y en qué banda cae la rueda.
│       ├── fuente_vibracion.dart  El acelerómetro, detrás de una interfaz.
│       ├── registro_vibracion.dart  Los vectores en la base.
│       └── servicio_vibracion.dart  Junta, resume y guarda cada ventana.
├── ui/
│   ├── formato.dart         Cómo se escribe un número para leerlo.
│   ├── pantalla_viaje.dart  La pantalla del viaje en curso.
│   ├── pantalla_combustible.dart  Consumo, factor y las cargas.
│   ├── pantalla_carga.dart  El formulario, para llenar al lado del surtidor.
│   ├── pantalla_vibracion.dart  Qué aprendió, y qué cambió.
│   ├── pantalla_sensores.dart   Qué ve el teléfono, en vivo.
│   ├── pantalla_respaldo.dart   Reporte y respaldo, con su advertencia.
│   └── pantalla_diagnostico.dart  ¿Esto anda? y los últimos viajes.
└── main.dart                Abre la base y dibuja.

test/                        339 casos. Corren sin emulador ni teléfono.
firestore.rules              Las reglas de la base remota. PLANTILLA: los
                             UID van como marcadores, este repo es público.
android/…/MainActivity.kt    El ÚNICO código nativo: el puente con
                             `GnssStatus`. No lo cubre el banco — ver
                             «Verificación previa».
.github/workflows/apk.yml    Verificación previa + APK + release.
```

## Sellos de versión

| Archivo | Sello | Dónde |
|---|---|---|
| Aplicación | `sitd-18` | `lib/core/version.dart` |
| Esquema de la base | `3` | `lib/core/db/esquema.dart` |

Ante una discrepancia entre esta tabla y el sello escrito adentro del archivo,
**manda el archivo**: esta tabla se copia a mano y se desactualiza en silencio.

**El esquema se toca agregando migraciones abajo, nunca editando una
publicada.** Van tres: la 0 → 1 con las cuatro tablas del principio, la 1 → 2
con `vibraciones` (tanda 5) y la 2 → 3 con el diagnóstico del viaje (tanda 7).
Una base vieja corre las que le faltan al abrir; una nueva corre las tres y
queda igual.

## Verificación previa

No es opcional. Es exactamente lo que corre el workflow, y si falla, no se
sube:

```bash
flutter analyze --fatal-infos --fatal-warnings
dart format --output=none --set-exit-if-changed .
flutter test
```

**Y hay un agujero, que conviene tener presente porque ya costó una corrida.**
Estos tres comandos corren **sin el SDK de Android**, así que no ven nada de la
compilación nativa: ni el Kotlin de `MainActivity.kt`, ni las exigencias de
versión de un paquete. El 2026-09-16 la corrida 17 falló en «Construir APK» con
los tres en verde — `permission_handler_android` pedía compilar contra la API 37
y el plugin de Gradle llega hasta la 36 — y el error hablaba de «AAR metadata»,
que no se parece en nada a un problema de versiones.

Lo que se puede hacer desde una sesión sin ese SDK, y se hace:

- leer el `build.gradle` del paquete en la caché de pub antes de confiar en una
  versión nueva (`~/.pub-cache/hosted/pub.dev/<paquete>/android/`), que es como
  se encontró aquel `compileSdk = 37` sin esperar otra corrida;
- mantener el código nativo **mínimo y defensivo**, y que el lado de Dart trate
  «el canal no contestó» como un estado normal y no como un error — así un
  problema en el Kotlin degrada el diagnóstico pero no impide medir.

## El error que costó tres días, y cómo se encontró

**`geolocator` miente en Android: `hasSpeed` y `hasAccuracy` valen `false`
siempre.** Es un error de `geolocator_android` 5.0.3 —`AndroidPosition.fromMap`
copia los números y pierde las banderas— y hacía que este proyecto descartara
**todas** las posiciones del GPS, en cualquier teléfono.

Dos viajes reales terminaron en cero metros con el receptor entregando una
posición por segundo. El diagnóstico apuntó tres días al receptor, a los
permisos, a HyperOS y al servicio en primer plano.

**Cómo se encontró, que es lo que vale para la próxima:** armando a mano el
mapa que manda el lado nativo y pasándolo por el traductor del paquete. Cinco
minutos:

```dart
final p = AndroidPosition.fromMap({
  'latitude': -34.9, 'longitude': -56.2, 'timestamp': 1789576665000,
  'accuracy': 7.5, 'speed': 12.3, 'speed_accuracy': 0.4,
});
// accuracy 7.5, speed 12.3 ... y hasAccuracy false, hasSpeed false.
```

La regla que queda: **cuando un contador dé cero y la causa parezca estar
afuera, probá la traducción con un dato fabricado antes de seguir buscando
afuera.** Un filtro que rechaza todo se ve igual que un sensor que no entrega
nada. Está en `fuente_gps_test.dart`, y si esa prueba empieza a fallar es que
lo arreglaron río arriba.

## Las cosas que sorprenden

**La distancia no se calcula sumando distancias.** Se integra la velocidad que
informa el receptor GPS, que sale del corrimiento Doppler de la portadora y
tiene un error de ~0,1 m/s. Sumar haversines entre posiciones consecutivas
parece lo obvio y es el error clásico: el ruido de posición siempre suma y
nunca resta, así que una camioneta detenida acumula kilómetros. Hay una prueba
dedicada a ese caso (`DETENIDO con ruido de GPS no acumula un metro`), y
comprueba las dos mitades: que la integración da cero y que el haversine da más
de cien metros.

**Una posición sin velocidad no es una camioneta quieta.** Android entrega
`speed == 0.0` cuando no tiene el dato, no un nulo. Copiarlo tal cual haría que
un receptor que todavía no fijó satélites se leyera como un vehículo detenido:
el viaje saldría corto y **nada lo diría**. Por eso se mira `hasSpeed`, esas
lecturas se cuentan aparte y la pantalla las muestra en «sin velocidad».

**Un viaje sin muestras no es un viaje de cero kilómetros.** Adentro de una
casa el receptor no fija satélites y el viaje termina en 0,0 km, que se lee
como «no anduvo» cuando lo que pasó es que nunca llegó una señal. Mientras no
hay una sola muestra buena, la pantalla dice qué está esperando; y en la lista
de viajes, uno sin muestras se muestra como **«Sin muestras»** y no como un
cero. Salió de la primera prueba real, un viaje de 13 segundos puertas adentro.

**Un viaje que no registra nada casi nunca es «el GPS no anda».** Son cuatro
cosas distintas que desde afuera se ven igual —un cero—: el receptor todavía no
fijó satélites, llega sin velocidad Doppler, llegan posiciones con más error
del tolerado, o el permiso quedó en «ubicación aproximada». La pantalla de
**Sensores** las distingue, y desde `sitd-6` la aplicación guarda el motivo de
cada descarte en vez de un contador mudo. El filtro de precisión, además, pasó
de 20 a 50 m: acá se integra la velocidad, no la posición, y un receptor puede
dar una posición con 40 m de error junto con una velocidad excelente.

**La vibración se compara sólo contra la misma velocidad.** Una falla mecánica
tiene frecuencia proporcional a las vueltas de la rueda: un desbalanceo a
60 km/h está cerca de 8 Hz y a 110 cerca de 15. Comparar el espectro de un
tramo de ruta con el de uno de ciudad haría que todo pareciera una anomalía. Por
eso la historia se guarda en **cubetas de 10 km/h**, y una ventana cuya
velocidad cambió de cubeta en el medio se descarta entera.

**Se guarda el módulo del acelerómetro, no un eje.** No se sabe cómo quedó
puesto el teléfono en la cabina —de costado, boca abajo, en un soporte
torcido—, y con un solo eje el mismo defecto daría números distintos según cómo
lo colgaron ese día.

**No se avisa por un viaje raro.** Un camino de tierra, una carga pesada o barro
pegado a una llanta alcanzan para mover una banda un viaje entero. Hacen falta
**tres viajes seguidos** con la misma banda de la misma cubeta fuera de lo
normal, y el aviso sale **al terminar el viaje, nunca manejando**. Además la
línea base se calcula dejando afuera esos tres viajes: si no, una falla que
empieza y se queda se iría metiendo de a poco en «lo normal» hasta dejar de
verse.

**El consumo se calcula de un tanque lleno al siguiente.** Es la única cuenta
que no depende de adivinar: un tanque sólo se sabe cuánto tiene cuando
rebalsa, así que entre dos llenados los litros que entraron son exactamente los
que se quemaron. Los litros de la carga que **abre** el tramo no cuentan —ésos
se quemaron antes— y una carga parcial no cierra el tramo, aunque sus litros
entren en él. El promedio de toda la historia pesa por kilómetro y no por
tramo: si no, una carga corta en ciudad valdría lo mismo que una tirada de
600 km.

**El par que calibra los neumáticos sale de un VIAJE, no de dos cargas.** Entre
dos cargas puede haber kilómetros que el GPS no vio —la aplicación cerrada, un
viaje que nadie empezó—, y esos kilómetros faltantes harían que el factor
saliera más chico de lo que es, sin que nada avise. Un viaje, en cambio, tiene
las dos medidas del mismo tramo: por eso la aplicación ofrece anotar el
odómetro al empezar y al terminar, y por eso nunca lo exige.

**El factor de neumáticos corrige al tablero, no al GPS.** El GPS ya mide la
distancia real. El que miente es el odómetro de fábrica, que cuenta vueltas de
rueda y las multiplica por la circunferencia que traía. Entonces
`km_real = km_tablero × k`, y `k` no se teclea: se aprende de la mediana de los
cocientes de los tramos largos.

**Las muestras crudas se guardan enteras, una por una.** Ocupan ~30 bytes y son
lo único que no se puede reconstruir. El total del viaje, en cambio, es un
derivado: `recalcular` lo rehace desde los puntos, así que el día que mejore el
filtro se recalculan todos los viajes viejos sin haber perdido nada.

## Requisitos de desarrollo

Flutter 3.47.4, JDK 17, SDK de Android. `minSdk` es **29** (Android 10) porque
el teléfono de destino es un Redmi Note 9, no el Redmi 15 con el que se
desarrolla.

Dependencias, y son seis: `sqlite3` (base local, sin generación de código),
`geolocator` (GPS y servicio en primer plano), `sensors_plus` (acelerómetro),
`share_plus` (sacar los datos del teléfono), `wakelock_plus` (que la pantalla
no se apague mientras se mide) y `path_provider` (dónde va el archivo de la
base). La FFT es propia: son
cuarenta líneas y sería el único paquete del proyecto que no habla con el
sistema operativo.

## Reglas del repositorio

En `CLAUDE.md`, incluido por qué este proyecto rompe la regla de «se edita
desde el teléfono» que siguen los otros cuatro del ecosistema.
