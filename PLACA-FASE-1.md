# La placa, Fase 1: leer el pedal y la vibración, y hablarle a la app — plan

> Estado: **plan, nada instalado ni escrito en código.** 13-nov-2026. Las piezas
> todavía no llegaron: el modelo del acelerómetro («creo que es el MPU») y el
> resto de los componentes **se confirman cuando lleguen**, y lo que dependa de
> eso está marcado **A CONFIRMAR**. Escrito por Claude a pedido de Mauro.
>
> Pedido de Mauro, 13-nov-2026: «en una primera etapa… conectar la ESP32 a los
> cables del acelerador en paralelo sin cambiar el circuito para que pueda
> hacer las lecturas y aprender de qué forma está operando». Y después: que las
> muestras no suban en vivo a un chat sino que **se guarden en el mismo soporte
> que usa la aplicación y se exporten junto con los viajes**, y que un
> acelerómetro conectado a la misma placa dé «lecturas más fijas que las del
> teléfono» y **alimente la misma APK**, para cruzar la información «de forma
> segura y consistente».

Este documento **complementa a `CRUCERO.md`** (§ 9, «La placa también le habla
al teléfono») y **cambia una sola decisión** de ese archivo; el § 1 dice cuál.
Su contenido tiene que vivir también en `placa.js` de `maurogasta-crypto/datos`:
**si cambia este archivo, cambia aquél en la misma tanda** (regla de `CRUCERO.md`).

## 1. Qué se decide, y qué cambia respecto de `CRUCERO.md`

**Se decide:** en la Fase 1 la placa **lee** el pedal (VPA y VPA2) **en
paralelo**, con alta impedancia, y lee un acelerómetro propio. **No manda nada**:
no hay relés, no hay DAC, no hay salidas hacia la ECU. Es la etapa 1 del § 7 de
`CRUCERO.md` («escuchar») hecha permanente.

**Lo que cambia.** `CRUCERO.md` § 9.1 decía que la caja básica lee sólo
señales que la camioneta ya da afuera (freno, tacómetro, velocidad) y que
«leer VPA y VPA2 con el arnés en Y pasó a la etapa del crucero». **Mauro lo
adelanta a la Fase 1**, porque lo que se quiere aprender primero es cómo se
comporta el pedal. Es razonable **con tres condiciones**, y sin ellas se vuelve
a la decisión anterior:

1. **Alta impedancia y una resistencia en serie pegada al punto de toma**
   (§ 4.1): la placa no carga la señal ni puede cortocircuitarla.
2. **El tester manda** (§ 8): lo que lee la placa tiene que coincidir con el
   tester antes de dar nada por bueno.
3. **Cualquier luz del motor o código de falla apaga todo**: se desconecta la
   placa y la camioneta queda como de fábrica. Es la prueba de que el paralelo
   no cambió el circuito.

**Lo que NO cambia:** el § 3 de `CRUCERO.md` entero (el teléfono no va en el
lazo del acelerador) y que en la Fase 1 **no existe ninguna salida**. Lo que el
teléfono pueda editar (§ 6.4 de acá) es sólo medida y confort, nunca seguridad.

## 2. Alcance

| Entra en la Fase 1 | No entra |
|---|---|
| Leer VPA y VPA2 en paralelo (alta impedancia) | Emular, cortar o intercalar el pedal (Fase 3) |
| Acelerómetro propio en un punto rígido, 500–1000 Hz (a confirmar con el modelo) | Relés, DAC, watchdog externo, comparador del freno |
| Contexto por optoacopladores: freno (STP), tacómetro (TACH), velocidad (SPD), contacto | Control crucero de cualquier tipo |
| Bluetooth BLE hacia la APK; guardado en la base de la app | Subir datos de la placa a la nube en vivo |
| Respaldo en microSD dentro de la placa | Mensajes del teléfono que cambien algo de seguridad (no existen) |
| Cruce con los viajes ya medidos por la app | Fusionar la vibración de la placa con la del teléfono (se **comparan**, § 7) |

## 3. Las piezas

| Pieza | Para qué | Estado |
|---|---|---|
| ESP32 DevKit (WROOM) en placa de borneras | el cerebro; dos núcleos y BLE | A CONFIRMAR modelo exacto |
| ADC externo ADS1115 (16 bits, I2C) | leer VPA y VPA2: el ADC interno del ESP32 es poco lineal, ruidoso y tolera 3,3 V | A CONFIRMAR |
| Acelerómetro «MPU» (¿MPU6050?) | vibración propia; **sube el techo del espectro de 100 Hz a 500 Hz** (ver `CRUCERO.md` § 9.2) | **A CONFIRMAR modelo** |
| 4 divisores: 68 kΩ + 100 kΩ al 1 % (señal y masa del pedal, por canal), + 100 nF en cada entrada | bajar los 5 V del pedal a ≤ 3,1 V sin cargarlo y leer diferencial contra la masa del pedal | a comprar (8 resistencias) |
| Módulo de 4 optoacopladores (PC817) | freno, tacómetro, velocidad y contacto, aislados | A CONFIRMAR |
| Módulo microSD (SPI) + tarjeta | respaldo si el Bluetooth se corta | recomendado |
| Reloj DS3231 | alinear sesiones con los viajes si el teléfono no está | opcional |
| Cargador USB de encendedor | alimentación; sólo da corriente con el contacto | a confirmar |
| Fichas macho/hembra del pedal, o una derivación fina soldada | tomar las señales sin cortar | ver § 4.2 |

**Pasar a Claude, cuando lleguen:** modelo exacto impreso en cada módulo, foto
del chip del acelerómetro y de su plaqueta, y qué dice la etiqueta del ESP32.
Con eso se fija todo lo marcado A CONFIRMAR.

## 4. Conexión eléctrica

### 4.1 El pedal, en paralelo y sin cargarlo

Cada señal (VPA y VPA2) baja por **una resistencia de 68 kΩ puesta en el mismo
punto de toma** y sigue hacia la placa por un cable fino, donde un divisor con
100 kΩ a masa la deja en 0,595 de su valor: **5,1 V → 3,03 V**, dentro de lo
que tolera el ADS1115 alimentado a 3,3 V (su límite es VDD + 0,3 V).

```
pedal VPA ──┬────────────── a la ECU (no se toca)
            │
          [68 kΩ]  ← pegada al punto de toma
            │
            ├────────[100 nF]── masa de la placa
            ├────────[100 kΩ]── masa de la placa
            │
            └──→ entrada A0 del ADS1115      (VPA2 igual → A1)
```

**Por qué la de 68 kΩ va en el punto de toma y no en la placa:** así el cable que
viaja a la placa lleva ya la señal dividida y, si se pela, se aplasta o se pone
en corto, lo máximo que pasa por la señal original son **5 V / 68 kΩ ≈ 75 µA**.
La ECU no lo nota. **Lo que esto no cubre** es un corto en el punto de toma
mismo, antes de la resistencia: por eso la ventanita se aísla con termocontraíble
y no sólo con cinta, y se comprueba con el tester que no haya continuidad hacia
ningún cable vecino ni hacia el chasis. Es la misma razón por la que `CRUCERO.md` exige que todo
corte sea por cable y no por programa: acá es que **todo fallo caiga del lado
seguro de forma física**.

**La ganancia real no es 0,595:** la impedancia de entrada del ADS1115 y las
tolerancias de las resistencias mueven unas décimas de por ciento. Se **calibra
contra el tester** (contacto puesto, pedal suelto / mitad / a fondo) y esos
factores se guardan con la sesión (§ 6.5), no en el programa.

**La masa del pedal NO se une a la masa de la placa.** La placa se alimenta del
encendedor, o sea que su masa es el chasis; la masa de los sensores del pedal
(EPA) es la que la ECU usa de referencia y puede no estar al mismo potencial.
Unirlas con un cable circula corriente por la masa de los sensores y **mueve la
lectura que hace la ECU**, que es justo lo que se quiere evitar. Por eso cada
canal se lee **diferencial** en el ADS1115: la entrada positiva es la señal
dividida (68 kΩ + 100 kΩ, como arriba) y la negativa es **la masa del pedal por
otro divisor idéntico** (68 kΩ + 100 kΩ a la masa de la placa). El conversor mide
la diferencia entre las dos, y por la masa del pedal sólo pasan los
microamperios que fija esa resistencia: no hay camino de corriente que la
perturbe. Usa los dos pares diferenciales del ADS1115 (A0‑A1 para VPA y A2‑A3
para VPA2). Se mide igual con el tester cuántos mV hay entre EPA y el chasis, y
se anota. **La placa nunca alimenta los sensores del pedal**: los alimenta la
ECU, y ningún cable de la placa se conecta a la alimentación de los sensores.

### 4.2 Cómo se hace la toma

Mauro decidió el 4-nov para las señales de sólo lectura: una ventanita en el
forro, soldada y aislada con buena cinta («pelando un poco el forro»). **Para
las del pedal se recomienda además la opción reversible**: un par de fichas
(macho y hembra) que se intercala y se saca, y la camioneta queda como de
fábrica. Es más cara y más segura, y es lo que se necesita igual en la Fase 3.
**Qué cable es cuál no se supone por el color**: se identifica con el manual de
reparación y se confirma con el tester antes de pelar nada. Los valores que
aparecen en `CRUCERO.md` § 8 son de otro motor Toyota y **no son los del 1KD**.

### 4.3 El acelerómetro

- Alimentado a 3,3 V desde el ESP32, por I2C (SDA/SCL), con su pin de
  «dato listo» (INT) a un pin del ESP32. La dirección I2C se fija con AD0
  (típico 0x68 para un MPU6050).
- **Atornillado a un punto rígido** (nunca con cinta ni adhesivo blando) y
  **siempre con la misma orientación**. La orientación se anota con la sesión.
- **Al arrancar, el firmware lee el registro de identidad (WHO_AM_I)** y lo
  manda a la app. Un MPU6050 original responde 0x68, un MPU6500 0x70 y un
  MPU9250 0x71, y **los módulos baratos suelen traer chips falsos o
  parecidos**: se guarda lo que responda, para no descubrir tres semanas
  después que los registros eran otros.
- Rango inicial ±4 g (unos 0,12 mg por paso en un MPU6050) y filtro interno
  puesto; **la frecuencia medida es la que se guarda, no la pedida** (§ 6.5).

### 4.4 Contexto por optoacopladores

Freno (STP), tacómetro (TACH), velocidad (SPD) y contacto entran por un módulo
de optoacopladores ya armado, aislados de la camioneta. Un pedal solo no dice si
el pie sube por un adelantamiento o por una cuesta: freno, RPM y velocidad
**dan el contexto sin el cual la lectura del pedal no se puede interpretar**.

### 4.5 Alimentación y arranque

Cargador USB de encendedor (sólo con contacto). **Al dar arranque, la tensión
cae y el ESP32 puede reiniciarse**: en la Fase 1 es aceptable y se espera. La
sesión se cierra, la placa vuelve y abre otra, y la app la reconoce como una
reconexión (§ 6.3). La fuente automotriz con protección contra picos queda para
cuando la placa mande sobre algo (`CRUCERO.md` § 9.1).

### 4.6 Pines (propuesta; se fija al armar, con las piezas en la mano)

| Función | Pin del ESP32 |
|---|---|
| I2C SDA / SCL (ADS1115 y acelerómetro) | 21 / 22 |
| INT del acelerómetro | 4 |
| microSD: CS / SCK / MISO / MOSI | 5 / 18 / 19 / 23 |
| STP / TACH / SPD / contacto (entradas con pull-up) | 32 / 33 / 25 / 26 |
| LED de estado (**única** salida) | 2 |

**Regla por construcción:** en la Fase 1 **ningún pin es una salida** salvo el
LED y el CS de la microSD. El banco de pruebas lo comprueba mirando el
firmware: cualquier salida fuera de esa lista rompe la prueba.

## 5. Lo que hace el firmware

- **Dos núcleos:** uno lee sensores y sella el tiempo; el otro habla por
  Bluetooth y escribe la microSD. Un cuelgue del Bluetooth no frena la lectura.
- **El tiempo se sella en la placa, en el instante de la muestra** (con el INT
  del acelerómetro y el reloj de microsegundos del ESP32), **nunca cuando el
  teléfono recibe el paquete**: el BLE tiene variación de demora y, si se sella
  del otro lado, el espectro se deforma.
- **Acelerómetro:** lee el FIFO del chip y manda lotes. El objetivo es 1 kHz
  con el filtro interno puesto, para que lo que está arriba de 500 Hz no se
  pliegue sobre lo medido (el mismo problema que ya documentó `MEDICION.md`
  con el teléfono a 200 Hz). **A CONFIRMAR** con el modelo y con la frecuencia
  que realmente entregue.
- **Pedal:** unas 100 muestras por segundo de cada canal, alternando entradas
  del ADS1115. Se manda el **valor crudo del conversor**, no milivoltios: el
  factor de calibración vive en el registro de la sesión (§ 6.5) y se puede
  rehacer después sin perder nada.
- **Digitales:** estado del freno y contacto con su instante, y pulsos de
  tacómetro y velocidad **contados por el hardware** (no por el programa).
- **Respaldo en microSD:** las mismas tramas que van por Bluetooth, en un
  archivo por sesión. Si el teléfono se cae, **no se pierde nada** y la app pide
  lo que le faltó al reconectar. Una herramienta (que escribe Claude) las
  convierte a CSV para analizarlas fuera de la app.

## 6. Bluetooth: cómo le habla la placa a la APK

### 6.1 BLE, no Bluetooth clásico

BLE consume menos, el ESP32 lo da completo y es lo que mejor soportan los
plugins de Flutter. Con 1 kHz × 3 ejes × 2 bytes son **unos 6 kB/s** más unos
0,4 kB/s del pedal: cabe con lotes de ~20 ms y un MTU negociado de 185–247
bytes. **Si en el Redmi Note 9 no se sostiene**, se baja a 500 Hz (y la placa
sigue guardando completo en la microSD). Eso se mide en la primera prueba, no
se supone.

### 6.2 La interfaz GATT

Un solo servicio de la placa, con cuatro características. **Los UUID de 128 bits
se generan una vez y se fijan en el firmware, en la app y en `placa.js`**; no se
inventan en este documento.

| Característica | Sentido | Qué lleva |
|---|---|---|
| Datos | placa → app (notificación) | tramas de acelerómetro, pedal y digitales |
| Estado | placa → app (lectura/notificación) | versión del firmware, WHO_AM_I, frecuencias medidas, tramas perdidas, hora de la placa, causa del último reinicio |
| Tiempo | lectura/escritura | sincronización de relojes (§ 6.3) |
| Control | app → placa (escritura) | **sólo** los parámetros del § 6.4 |

**Seguridad de la conexión:** emparejamiento con clave (vinculación) y **una sola
conexión central a la vez**. La app sólo acepta la placa que se emparejó. El
Control exige estar emparejado. La Fase 1 no tiene salidas, así que **un mensaje
malicioso o equivocado no puede mover nada del vehículo**: lo peor que puede
hacer es desordenar una medición, y por eso todo cambio queda escrito (§ 6.4).

### 6.3 Un solo reloj

La placa tiene su propio reloj monótono en microsegundos; la app, el del
teléfono. Para cruzarlos:

- Al conectar, y cada cierto tiempo, la app lee el reloj de la placa varias
  veces y guarda el **desfase con la menor demora de ida y vuelta**.
- **Los datos crudos se guardan en el tiempo de la placa** y el desfase se
  guarda **aparte, como una tabla de puntos** (tiempo de la placa → tiempo del
  teléfono). Al leer, se convierte. Es la regla de siempre —**los derivados no
  se guardan**— y evita que un sincronizado mejorado mañana sea imposible
  porque el de hoy ya se «horneó» en las muestras.
- Un reinicio de la placa (el arranque, § 4.5) abre **una sesión nueva** con
  su propio desfase.

### 6.4 Lo que el teléfono puede editar, y lo que no

Es el § 9.3 de `CRUCERO.md`, sin cambios:

- **Sí:** cada cuánto manda cada señal, rango y filtro del acelerómetro,
  umbrales para pedir una grabación. Con tres condiciones: el firmware **recorta
  cada parámetro a su rango**, un cambio **que altera cómo se mide** se acepta
  **sólo con el vehículo detenido**, y **queda escrito de los dos lados** (la
  placa anota qué cambió y cuándo; la app lo guarda con el viaje). Un número
  tocado que nadie anotó vuelve incomparables todos los viajes siguientes.
- **No:** nada de seguridad. En la Fase 1 no existe en la placa, y en la Fase 3
  vive en el hardware y el firmware, sin mensaje que lo cambie.

### 6.5 La trama

Todas las tramas llevan lo mismo adelante y un control al final:

| Campo | Bytes | Para qué |
|---|---|---|
| marca y versión del formato | 2 | reconocer y poder cambiar el formato sin romper lo viejo |
| tipo | 1 | acelerómetro, pedal, digitales, estado |
| número de secuencia | 4 | **detectar tramas perdidas**: un salto es un faltante y se guarda |
| tiempo de la primera muestra (µs de la placa) | 8 | sellado en la placa |
| tiempo hasta la última muestra (µs) | 4 | **la frecuencia medida de cada trama = (n−1) / ese intervalo**; esa se guarda |
| n de muestras | 2 | |
| muestras | n × (6 o 4) | acelerómetro: x, y, z; pedal: VPA, VPA2 (crudos) |
| CRC | 2 | una trama dañada se descarta y se cuenta |

**Registro de la sesión** (la app lo guarda al abrir cada una): versión del
firmware, modelo y WHO_AM_I del acelerómetro, rango y filtro, **factor de
calibración de cada canal del pedal** (y contra qué tester se calibró), el
desfase de reloj y su historia, y la orientación del montaje.

## 7. En la app

### 7.1 Plugin y permisos

Falta todo esto, y **el zip del 4-nov no lo trae** (no hay plugin Bluetooth en
`pubspec.yaml` ni permisos en el manifiesto; el `enlace.dart` que existe habla
con la Pizarra del otro teléfono, no con la placa):

- Plugin BLE de Flutter **a elegir y verificar la versión al hacer la tanda**
  (candidato: `flutter_blue_plus`).
- **Android 10 (el Note 9, `minSdk 29`)**: el escaneo BLE exige el permiso de
  ubicación, que la app ya pide por el GPS. **Android 12 en adelante**: exige
  `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT`. El Redmi 15 y el Note 9 se comportan
  distinto; **se prueba en los dos**.
- **HyperOS:** la conexión tiene que vivir dentro del servicio en primer plano
  que ya existe (`CLAUDE.md`, § MIUI/HyperOS), no en uno aparte: un servicio
  Bluetooth que el sistema mata en segundo plano es la forma más segura de
  perder muestras sin darse cuenta.

### 7.2 Dos fuentes nuevas, con la forma que ya existe

- **`FuenteDeVibracion`** ya es la interfaz del acelerómetro y emite `Sacudon`
  (tiempo, x, y, z). **La placa es otra implementación de esa interfaz**, y
  todo el motor de análisis (espectro, bandas, líneas, línea base) funciona sin
  tocarse. Es lo que ya prevé `CRUCERO.md` § 9.2 («el motor de análisis no tiene
  que saber de dónde salen los números»).
- **Una interfaz nueva para el pedal** (`FuenteDePedal`), con el mismo
  criterio: **el banco de pruebas tiene que poder conducir una camioneta sin
  camioneta**. Se hace una fuente falsa que reproduce un CSV de una sesión
  (la herramienta del § 5 los genera), y las pruebas corren sin hardware.

### 7.3 Dónde se guarda

Se sigue la regla del esquema: **nunca se edita una migración publicada; se
agrega una abajo y sube `versionEsquema`** (hoy 13, así que la de la placa sería
la 14, **a confirmar contra el repositorio vivo** el día que se haga).

Tablas propuestas (nombres y columnas **a revisar** al implementar):

- **`placa_sesiones`**: una por conexión de la placa, con el registro del § 6.5
  y a qué viaje pertenece (puede no haber viaje).
- **`placa_pedal`**: el pedal **crudo y completo**, en bloques (un BLOB por
  intervalo, no una fila por muestra). A 100 Hz son unos **1,4 MB por hora**.
- **`placa_digitales`**: freno, contacto y conteos, con su instante.
- **`placa_vibracion`**: lo derivado del acelerómetro con el **mismo formato de
  ventana que `vibraciones`** (bandas, picos, líneas), con `origen = 'placa'`.
- **Grabaciones crudas de 10 s del acelerómetro de la placa**, con el mismo
  mecanismo que ya tiene `grabaciones` (cuando una línea se sale o cuando se
  toca «Grabar»), en lugar de guardar todo: a 1 kHz son unos **21 MB por hora**
  y no entran en una copia de la base.

**Decisión pendiente de Mauro (§ 10):** guardar el **pedal completo** y el
acelerómetro **derivado + grabaciones de 10 s** es lo que se recomienda, porque
lo que se quiere aprender del pedal es justamente su comportamiento fino, y el
espectro del acelerómetro ya se resume bien en bandas y líneas.

### 7.4 Exportación y nube

- **Todo viaja con los viajes**: entra en la copia completa de la base y en la
  importación, que **suma sin reemplazar**. Cada tabla nueva se agrega al
  importador, al saneado y a sus pruebas **en la misma tanda**: una tabla que
  se puede sacar y no devolver es un error que este proyecto ya pagó.
- **La nube:** los reportes se resumen (porcentajes de pedal por zona, relación
  VPA2/VPA, tramas perdidas, frecuencias medidas); **no se suben las muestras
  del pedal a Firestore** (un documento no pasa de 1 MiB, y hay un cupo). Los
  1,4 MB por hora quedan en el teléfono y en la copia completa de la base.
- **Nunca coordenadas** en nada de la placa, como en el resto del proyecto.
- **Todo lo que mide la placa va marcado como de la placa** y **no se presenta
  como dato de la ECU**: es una tensión leída en un cable, no un mensaje del
  vehículo.

### 7.5 Cruce con los viajes, sin mezclar

- **La placa es otra clase de muestreo.** Sus ventanas **no se comparan con las
  del teléfono** y la línea base de la placa **se aprende desde cero**, igual
  que pasó con los 50 y los 200 Hz de `sitd-42`.
- **La frecuencia guardada es la medida, no la pedida.**
- **Los dos acelerómetros del viaje se COMPARAN, no se fusionan**
  (el criterio de «Tres teléfonos en el mismo viaje», `MEDICION.md`): cuando el
  teléfono y la placa ven el mismo evento, se mide cuánto coinciden. Es la
  primera prueba de que la placa agrega valor y de que el sincronizado de
  reloj sirve.
- **Lo que no se borra sigue contando** si la placa se desconecta a mitad de un
  viaje: el viaje se mide igual con el teléfono, y el hueco de la placa queda
  marcado como faltante.

**Preguntas que esto permite responder** (y que hoy no se pueden): cómo se
relaciona el pedal con las RPM contadas y con el consumo del tramo; si hay
vibración que sólo aparece con carga alta de pedal; si el camino áspero se
separa de «motor haciendo fuerza» (`CRUCERO.md` § 9.2, «Posición del pedal»);
y cuánto se parecen VPA y VPA2 entre sí, que es **el dato que hay que tener
antes de diseñar la Fase 3**.

## 8. Pruebas, por etapas (no se saltea ninguna)

0. **En la mesa, sin camioneta.** ESP32, ADS1115 y acelerómetro alimentados
   por USB, con un potenciómetro que simula el pedal. Se comprueba la lectura
   del ADC contra el tester, el divisor, y el Bluetooth hasta la app (con la
   fuente falsa y con la real). **Primera medición de si el Note 9 sostiene el
   flujo.**
1. **En la camioneta, motor apagado, contacto puesto.** Primero **medir con el
   tester** VPA y VPA2 con el pedal suelto, a la mitad y a fondo. Después
   conectar la placa y repetir: **los valores de la placa tienen que
   coincidir con el tester** (**±20 mV es un punto de partida propuesto, se
   fija con la primera medición**). **Mirar el tablero:** ninguna luz.
2. **Motor en marcha, en ralentí, freno de mano.** La luz del motor sigue
   apagada y las RPM siguen al pie como siempre.
3. **Viajes cortos.** La camioneta anda **exactamente igual** que sin la placa.
4. **Viajes normales: aprendizaje.** Recién acá se miran los datos para
   aprender.

**Si en cualquier etapa aparece una luz o un código de falla** (el típico es el
de las dos señales del pedal que no se corresponden, **P2135**, que ya se vio
en intentos caseros con Arduino, `CRUCERO.md` § 8): **se desconecta la placa**
y se vuelve a la etapa anterior. Que la camioneta quede como de fábrica con
sólo sacar la placa es la prueba de que la conexión en paralelo **no cambió el
circuito**.

## 9. Lo que puede salir mal

| Riesgo | Qué lo cubre |
|---|---|
| La ECU ve la placa y marca falla en el pedal | Alta impedancia, 68 kΩ en el punto de toma, tester antes y después, y desconexión inmediata |
| Diferencia de masa entre el pedal y el chasis | Lectura diferencial: la masa del pedal entra por un divisor de alta impedancia y **nunca se une a la masa de la placa** (§ 4.1) |
| Un cable mal identificado (12 V, o la alimentación de los sensores, llega a una entrada) | Cada entrada pasa por 68 kΩ pegada a la toma (limita la corriente), se identifica con manual y tester **antes** de pelar, y se verifica con la placa desenchufada |
| La placa apagada con las señales del pedal presentes | Entra una corriente de decenas de µA por los diodos de protección del conversor y puede mantener alimentada la placa a medias: se **desconectan las tomas** al dejar la camioneta con la placa fuera, o se agrega un diodo en la entrada (a decidir con el modelo exacto) |
| Picos del alternador por el encendedor | Cargador de buena marca; la fuente automotriz con protección de picos queda para cuando la placa mande algo |
| Chip de acelerómetro distinto del esperado | Se lee y guarda WHO_AM_I; los registros se verifican al arrancar |
| El Bluetooth se corta o HyperOS lo mata | Respaldo en microSD, número de secuencia, la conexión dentro del servicio en primer plano |
| El reloj de la placa se desfasa del teléfono | Tabla de puntos de sincronización y datos crudos en el tiempo de la placa |
| Reinicio de la placa al dar arranque | Es esperado: sesión nueva, la app lo reconoce |
| Ruido de encendido o de alternador | Capacitores en las entradas, montaje del acelerómetro, y se **mira** en las primeras mediciones |
| La base crece demasiado | Pedal en bloques (1,4 MB/h), acelerómetro derivado, grabaciones de 10 s con tope diario |
| Un parámetro tocado que nadie anotó | Todo cambio queda escrito en la placa y en la app |

**Seguro y habilitación:** la Fase 1 sólo lee, pero igual se está conectando un
cable a una señal de mando del vehículo. Conviene dejar la toma **reversible**
(las fichas del § 4.2) y **preguntar antes de la Fase 3**, como ya dice
`CRUCERO.md` § 5.

## 10. Lo que hay que decidir o traer (Mauro)

1. **Los modelos exactos** de lo que llegue (ver § 3), con fotos.
2. Si la microSD entra en la Fase 1 (se recomienda).
3. **Pedal completo + acelerómetro derivado** (lo que se recomienda) o todo
   completo en el teléfono (§ 7.3).
4. Fichas reversibles o derivación soldada para el pedal (§ 4.2).
5. Si el reloj DS3231 entra o se usa sólo el del teléfono.

## 11. Qué archivos toca esto cuando se implemente (la tanda)

- **Nuevo:** `lib/features/placa/` (fuente BLE, tramas, sesión, sincronizado de
  reloj, fuente falsa para el banco) y sus pruebas en `test/`.
- **`lib/core/db/esquema.dart`:** una migración nueva abajo y `versionEsquema`
  +1; `test/esquema_test.dart` la revisa.
- **`importar.dart`, `reporte.dart`, `saneado.dart`** y sus pruebas: cada tabla
  nueva sale y vuelve a entrar.
- **`pubspec.yaml`, `AndroidManifest.xml`:** el plugin BLE y los permisos.
- **`lib/core/version.dart`:** el sello de la tanda.
- **`README.md` y `CLAUDE.md`:** una fila en la tabla de documentación técnica
  y una regla corta que apunte a este archivo.
- **`placa.js` en `maurogasta-crypto/datos`**, en la **misma tanda**.

**Cambios que este documento pide en `CRUCERO.md`:**

- § 9.1, donde dice «**No toca el pedal**: leer VPA y VPA2 con el arnés en Y
  pasó a la etapa del crucero», poner: «**No lo comanda**: lee VPA y VPA2 en
  paralelo y de alta impedancia desde la Fase 1 (Mauro, 13-nov-2026; ver
  `PLACA-FASE-1.md`). Lo que pasó a la etapa del crucero es cortarlas e
  intercalarlas».
- Donde el mismo párrafo dice «La placa de sensores **no toca el pedal**, así
  que puede existir antes», cambiar a «no **comanda** el pedal».

**Para `CLAUDE.md`, la fila del índice:**

| `PLACA-FASE-1.md` | la Fase 1 de la placa (13-nov-2026): leer el pedal en paralelo y un acelerómetro propio, cómo se conecta, cómo le habla a la APK por BLE, dónde se guarda y cómo se cruza con los viajes sin mezclar |

## Fuentes y lo que no se verificó

- Lo que dice este documento de la app sale de leer el zip del repositorio del
  4-nov-2026 (`sitd-57`, esquema 13): **si cambió desde entonces, hay que
  revisarlo antes de implementar.**
- Los números de las piezas (impedancias, rangos, direcciones, pines) son
  **valores típicos de las hojas de datos de cada chip, no medidos en esta
  camioneta**: se confirman con las piezas en la mano.
- **Nada de lo del pedal es del 1KD**: se mide en la camioneta (`CRUCERO.md`
  § 6 y § 8).
