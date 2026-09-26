# La ciencia de lo que muestra el panel

Qué significa cada número de **Sensores → Probar la medición**, de dónde sale
la cuenta, y qué se puede y qué no se puede concluir con él.

Está escrito porque **el 2026-09-22 la auditoría encontró seis números mal**,
todos del mismo tipo: se escribieron con una cubierta genérica, antes de que
Mauro midiera la suya, y cuando el número medido entró al proyecto nadie volvió
a los lugares donde ya estaba copiado.

| Dónde | Decía | Es |
|---|---|---|
| `espectro.dart` | 8 Hz a 60 km/h | 6,98 |
| `espectro.dart` | 15 Hz a 110 km/h | 12,80 |
| `ventana.dart` | 8 Hz a 60 km/h | 6,98 |
| `ventana.dart` | 15 Hz a 110 km/h | 12,80 |
| `calidad.dart` | 14,5 Hz a 120 km/h | 13,96 |
| `README.md` y `CLAUDE.md` | «cerca de 8 y cerca de 15» | 6,98 y 12,80 |

**La primera pasada encontró cuatro y la segunda —revisando coherencia, el
mismo día— encontró los otros dos**, que estaban en la documentación. Eso es el
argumento entero: un número repetido diverge, y ni siquiera se termina de
corregir de una sola vez. Es el mismo error que este ecosistema ya pagó con los
sellos de versión y con el texto de las reglas.

**Y el número correcto ya existía en el proyecto**: `test/cobertura_test.dart`
usaba 7,56 y 12,8 desde antes. O sea que la verdad y la mentira convivían en el
mismo repositorio, cada una en su archivo.

Lo que sigue tiene su banco de pruebas en `test/rueda_test.dart`, y **lo que
ahí se comprueba no es que el código haga lo que el código hace**: son valores
calculados a mano de la geometría, escritos como literales. Si alguien vuelve a
escribir un número redondo «que estaba bien», falla.

---

## Los datos de partida

| Qué | Valor | De dónde sale |
|---|---|---|
| Diámetro de rueda **bajo carga** | 0,76 m | lo midió Mauro el 2026-09-19 |
| Circunferencia | 2,3876 m | `π × 0,76` |
| Muestreo real del acelerómetro | **49,85 Hz** | medido sobre 1060 vectores de viajes reales |
| Techo del espectro (Nyquist) | **24,93 Hz** | `49,85 / 2` |
| Ventana de análisis | 251 muestras = 5,035 s | `espectro.dart` |
| Cilindros / tiempos | 4 / 4 | 1KD-FTV |
| Relación del diferencial | ≈ 3,583 | **de catálogo, no medida** |

**El diámetro es el medido y no el de catálogo, y la diferencia es el 5,3 %.**
La cubierta es una 265/70R17, que sin peso encima da 80,3 cm. Ese achatamiento
es más grande que el efecto que busca medir el factor de neumáticos, y es el
motivo entero por el que ese factor **se aprende de los viajes** en vez de
calcularse de la medida de la cubierta.

**Ojo con el 49,85.** Hasta el 2026-09-22 el `CLAUDE.md` decía 72,3 Hz, que es
lo que midió el panel de sensores mirando el stream a secas. Midiendo un viaje
—con la aplicación haciendo otras cosas— el acelerómetro entrega 49,85. La que
manda para el espectro es la segunda, porque es la que se usó para calcular
todo lo guardado.

---

## Indicador por indicador

### Entrega — la frecuencia real

```
hz = (muestras − 1) × 10⁶ / (último_µs − primer_µs)
```

Sale del tramo completo y no del promedio de los intervalos: así **un hueco
pesa lo que tiene que pesar** en vez de perderse entre cientos de intervalos
buenos.

**No es el período que se pidió.** Android trata el período como una
sugerencia. Pidiendo 20 ms (`game`), este teléfono entrega cada 20,06.

### Techo del espectro — Nyquist

```
nyquist = hz / 2
```

**Todo lo que está por encima no es que se vea mal: aparece abajo, donde no
está.** Ver «El motor», más abajo.

### Intervalo e irregularidad

```
irregularidad = (p95 − p5) / mediana        0,00 es un metrónomo
```

Una FFT **supone muestras igualmente espaciadas**. Si el sistema entrega a los
tirones, el espectro se embarra y el resultado son números con forma de dato.

Es relativo para que valga lo mismo a 50 Hz que a 400.

> **Este número se definía mal.** Era `p95 / mediana`, que se degenera: cuando
> los intervalos toman sólo dos valores —exactamente lo que pasa si el sello de
> tiempo viene redondeado al milisegundo— la mediana puede caer sobre el valor
> alto y el cociente da 1,00, o sea «perfecto» sobre la medición más desprolija
> posible. Con el ancho de la distribución eso no puede pasar.

**Y por eso el instante se marca en microsegundos.** A 400 Hz el intervalo son
2,5 ms; un sello al milisegundo lo convierte en 2 o en 3, y ese redondeo **solo**
se vería como un 50 % de irregularidad que no existe: el instrumento midiendo
su propia regla.

### Muestras que faltaron

```
faltaron = Σ máx(0, redondear(dt / mediana) − 1)
```

Un intervalo del doble de la mediana es **una** muestra que no llegó; uno del
triple, dos.

> El primer intento usaba un umbral de 2,5 × la mediana «para no contar de
> más», y con eso se perdía justo el caso más común: **una sola muestra
> faltante da exactamente 2×**.

**Con mucha irregularidad este número y el anterior se confunden**, y no hay
forma de separarlos: un intervalo largo puede ser una muestra que faltó o una
que llegó tarde. Si los dos están altos, la conclusión correcta es la misma —
este modo no entrega bien.

### Saturadas

Cuántas muestras quedaron **pegadas al mismo valor máximo, en posiciones
consecutivas**. Una señal recortada contra el fondo de escala del sensor deja
una meseta plana, y esa meseta le inventa armónicos que no existen.

> Se contaba por **cercanía** al máximo, y con eso una senoidal perfectamente
> limpia daba un 6 % de «saturadas»: una senoidal pasa mucho tiempo cerca de su
> pico. Lo que delata al recorte son los valores idénticos **repetidos en
> muestras vecinas**, que una señal analógica no hace nunca.

Si esto deja de ser cero con el motor en marcha, el soporte le está pegando al
tope: hay que amortiguarlo o moverlo.

### Energía (RMS)

```
rms = √( media( (aᵢ − ā)² ) )
```

Se le saca la media primero, porque **la media del módulo de un acelerómetro es
la gravedad** (9,8 m/s²) y taparía todo lo demás.

**Sirve para ver si un soporte transmite más que otro, y NO para decir cuál es
mejor**: un soporte flojo también sacude mucho, y eso no es señal.

### Pico dominante, con su margen

El bin más alto del espectro, saltando los dos primeros —el 0 es la continua y
el 1 arrastra lo que queda de la media; sin saltearlos el «pico dominante» de
cualquier medición sería siempre el bin 0.

```
frecuencia del bin k = k × nyquist / cantidad_de_bins
```

**El margen no es el espaciado entre bins, y confundirlos es el error clásico.**
La FFT rellena con ceros hasta la próxima potencia de dos (251 → 256), y eso
junta los bins — pero **rellenar interpola, no agrega información**:

```
espaciado de bins  = 49,85 / 256  = 0,195 Hz     ← el número engañoso
resolución real    = 1,5 / 5,035 s = 0,298 Hz    ← la verdadera
```

El 1,5 es el ensanchamiento del lóbulo que mete la ventana de Hann. Dos tonos
separados menos de 0,3 Hz se ven como uno solo, **por más bins que haya**. Por
eso el panel muestra `16,8 ± 0,3 Hz` y no `16,82 Hz`.

### Nitidez del pico

```
nitidez = magnitud del pico / mediana del espectro
```

**Es el número para comparar soportes**, y el único de todos que no se puede
adivinar sin medirlo. Un soporte rígido da un pico angosto y alto; uno blando
lo desparrama. La energía total no sirve para esto: mide cuánto sacude, no
cuánto se distingue.

### Motor visible hasta — en RPM

Un 4 cilindros de 4 tiempos hace **dos explosiones por vuelta de cigüeñal**
(cuatro cilindros cada dos vueltas):

```
f_encendido = 2 × RPM/60 = RPM / 30
```

Dado vuelta en el techo del espectro:

```
RPM máximo visible = nyquist × 30
```

A 49,85 Hz de muestreo son **748 RPM**: ni el ralentí, que en un 1KD anda por
los 750-800.

**Y lo que no entra aparece abajo.** Una frecuencia `f` muestreada a `fs`
aparece en `|f − fs·redondear(f/fs)|`:

| RPM | Encendido | Aparece en | Cae en |
|---|---|---|---|
| 800 | 26,7 Hz | 23,2 Hz | banda 17-25 |
| 1600 | 53,3 Hz | 3,5 Hz | banda 2-4 |
| 2000 | 66,7 Hz | **16,8 Hz** | banda 13-17 |
| 2500 | 83,3 Hz | **16,4 Hz** | banda 13-17 |

O sea que **las bandas 1, 6 y 7 llevan adentro un pedazo del motor**, y cuánto
depende de en qué vuelta iba — que es justo lo que no se está midiendo. Sin
tacómetro no hay forma de descontarlo.

### Rueda visible hasta — en km/h

```
f_rueda = (km/h / 3,6) / 2,3876
v_máxima = nyquist × 3,6 × 2,3876
```

A 49,85 Hz el 1× de la rueda llega a Nyquist recién a **214 km/h**, así que
entra siempre.

---

## Qué componente se puede distinguir, y hasta qué velocidad

Todo lo que gira lo hace en **múltiplos de la vuelta de rueda** (órdenes):

| Componente | Orden | A 49,85 Hz se ve hasta |
|---|---|---|
| Desbalanceo de rueda | 1× | 214 km/h — **siempre** |
| Ovalización, llanta doblada | 2× | 107 km/h |
| Cardán | ≈ 3,58× | **60 km/h** (y sale de la banda de 17 Hz a 41) |
| Bamboleo de rueda | 10-15 Hz, fijo | siempre, pero pisa al 1× arriba de 90 |
| Suspensión, carrocería | 1-2 Hz | siempre (es la banda de abajo) |
| Rodamientos de rueda | 3 a 12× | **no, ni cerca** |
| Motor | RPM/30 | **no, ni a ralentí** |

> **El comentario de `espectro.dart` decía que el cardán vivía en la zona de 4
> a 17 Hz junto con las ruedas.** No: gira 3,58 veces por vuelta de rueda, así
> que se sale de los 17 Hz arriba de unos 41 km/h. Con este muestreo el cardán
> sólo es observable andando despacio, y eso no estaba dicho en ningún lado.

**Los rodamientos necesitan otra cosa.** Sus frecuencias características están
entre 3 y 12 veces la vuelta de rueda —21 a 84 Hz a 60 km/h— y el diagnóstico
clásico usa análisis de envolvente a varios kHz. No es un problema de umbral:
la información no está en la señal.

---

## Las bandas, y dos cosas que hay que saber para leerlas

Los bordes son `0,5 · 2 · 4 · 6 · 8 · 10 · 13 · 17 · 25` Hz.

**Los anchos no son parejos**: 1,5 · 2 · 2 · 2 · 2 · 3 · 4 · **8**. Lo que se
guarda es la **suma** de cada banda, no la densidad, así que la banda de arriba
junta cuatro veces más bins que las del medio sólo por ser más ancha. Para el
detector no importa —compara cada banda contra sí misma— pero **para leer un
vector con los ojos hay que dividir por el ancho**.

**El borde de arriba se pasa de Nyquist** por 0,07 Hz. Es chico y no cambia
nada; está dicho para que nadie lo descubra dos veces.

Y de acá sale el motivo de las cubetas de velocidad: el **mismo** defecto cae
en bandas distintas según a qué velocidad se ande.

| Cubeta | km/h | f de rueda | El 1× cae en |
|---|---|---|---|
| 0 | 20-30 | 2,91 Hz | banda 1 |
| 2 | 40-50 | 5,24 Hz | banda 2 |
| 4 | 60-70 | 7,56 Hz | banda 3 |
| 6 | 80-90 | 9,89 Hz | banda 4 |
| 8 | 100-110 | 12,22 Hz | banda 5 |

Comparar espectros de velocidades distintas haría que todo fuera anomalía.

---

## Lo que se puede sacar de la vibración, medido (2026-09-26)

Mauro lo preguntó sin rodeos: «el camino aporta vibraciones más fuertes que el
motor y la transmisión — ¿los datos permiten filtrar y obtener información, o
no es posible detectar comportamientos fiables con este sensor?». Se contestó
con las **1299 ventanas reales** de once viajes. Lo que se guarda por ventana
son ocho bandas de energía, no la señal, así que la pregunta concreta fue si
esos ocho números separan el camino de la mecánica.

**1 · El camino se puede filtrar.** Un camino áspero sube todas las bandas
parejo. Si en vez de cuánta energía hay se mira **cómo se reparte** —cada banda
dividida por su ancho, y todo dividido por el total, para que sume uno—, la
aspereza se descuenta sola. La dispersión dentro de una cubeta baja de 53–73 %
a 28 % en ciudad, y de 32–43 % a 26–32 % en ruta.

**2 · Esa forma se repite de un viaje a otro**, que es lo que de verdad mide un
detector. Tomando la mediana de cada viaje por cubeta, varía un 7–8 % entre
viajes a 20–50 km/h. Con el umbral de seis desvíos, eso deja ver un cambio de
**40–46 %** en cualquier banda. Con la energía, la misma prueba daba 95 %, 154 %
y 186 %: una banda tenía que duplicarse o triplicarse. **Desde `sitd-33` el
detector compara la forma** (`formaDelEspectro` en `analisis.dart`).

**3 · No aparece nada que siga a la rueda.** Un desbalanceo cambia de banda al
acelerar, porque su frecuencia es la vuelta de rueda; el camino no. La banda
donde tendría que caer la rueda fue la de mayor exceso en **2 de 10** cubetas.
Lo que sí aparece es un exceso **fijo entre 4 y 6 Hz**, de 1,3 a 1,7 veces lo
habitual entre 20 y 80 km/h, que no se corre con la velocidad: una
**resonancia**, muy probablemente del soporte del teléfono o de la cabina. Por
encima de 80 km/h el exceso pasa a 0,5–4 Hz, que es el cabeceo de la
carrocería en las ondulaciones de la ruta.

**Lo que eso quiere decir.** El sensor sirve para saber que **algo cambió** en
la camioneta comparada consigo misma, que es para lo que se diseñó. No sirve,
con lo que hay, para decir **qué pieza**. Y que no aparezca la rueda tiene dos
lecturas que hoy no se pueden separar: o las ruedas están bien, o la resonancia
de 4–6 Hz tapa lo que haya, justo donde cae la rueda a 30–50 km/h.

**Lo que no se pudo medir.** Por encima de 60 km/h no hay cuatro viajes con
suficientes ventanas en una misma cubeta —sólo los dos de ruta—, así que la
repetibilidad en ruta queda sin comprobar. La cubeta de 50–60 tiene tres
viajes y su número no es confiable.

**Cómo se separan las dos lecturas:** con un caso conocido. El más seguro es
natural — la próxima vez que se balanceen las ruedas, un viaje igual antes y
otro después. Y la resonancia se ataca con «Probar la medición»: si un soporte
más rígido la corre de lugar, la rueda queda a la vista.

---

## Lo que este panel NO contesta

**Dónde conviene poner el teléfono.** No hay un mejor soporte: hay uno mejor
para cada cosa. La palanca de cambios está atornillada a la caja y muestra el
motor mucho mejor que el tablero, y al mismo tiempo es un voladizo con
resonancia propia y se mueve cuando uno cambia de marcha. Por eso el panel
**mide** en vez de recomendar. *(Mauro la descartó el 2026-09-22 y siguió con
el soporte.)*

**Si la camioneta está bien.** Esto mide el sensor, no el vehículo. Que el
espectro sea parejo puede querer decir que no hay defecto o que el soporte lo
está amortiguando, y sólo comparando dos soportes en la misma situación se
puede separar una cosa de la otra.

**Un puntaje único.** A propósito: que falte frecuencia se arregla pidiendo
otro modo, que sobre irregularidad no se arregla desde la aplicación, y que
sature se arregla moviendo el teléfono. Un número solo taparía los tres.

---

## Lo que falta medir, y por qué vale más que todo lo demás

**Qué entrega el modo «lo más rápido».** El sensor da más de lo que se le pide:
pidiendo 50 Hz entrega 49,85 con `game`, y nunca se midió `fastest`. Si fueran
200 Hz, el techo sube a 100 y:

- el **tacómetro** sale del acelerómetro solo, sin micrófono y sin la etapa E;
- con RPM y velocidad, la **relación total** (`RPM × 3,6 × C / (60 × v)`) se
  agrupa sola en cinco montoncitos que **son** las relaciones de la caja —no
  hay que saberlas de fábrica, igual que el factor de neumáticos;
- y con eso el **indicador de cambio** deja de ser una idea.

Es `hilux:V1` en el panel, y es una medición de una tarde.

**Una advertencia sobre el indicador de cambio**, para cuando llegue: «el
momento ideal» son tres respuestas distintas —máxima aceleración (cerca de la
potencia máxima), mínimo consumo (lo más temprano que el motor tire sin
ahogarse) y quedarse en la meseta de par— y un indicador honesto tiene que
decir para cuál está optimizando.

---

## La otra mejora que no depende de nada de esto

**Remuestrear el espectro en órdenes en vez de en hertz.** Hoy un defecto de
rueda se mueve de banda según la velocidad, y por eso hacen falta diez cubetas
para poder comparar. Pero `f_rueda` se conoce exactamente —la velocidad Doppler
es buena a 0,1 m/s y la circunferencia está medida—, así que se puede
remuestrear en múltiplos de la vuelta de rueda: orden 1 el desbalanceo, orden 2
la ovalización, orden 3,58 el cardán.

Con eso un defecto cae **en la misma banda a cualquier velocidad**. Las cubetas
siguen sirviendo para normalizar amplitud —que sí crece con la velocidad— pero
dejan de hacer falta para alinear frecuencia, y las 1060 ventanas que hoy están
repartidas en diez cubetas pasan a aportar todas a las mismas bandas.
