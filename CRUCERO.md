# Control crucero para la Hilux — plan

> Estado: **plan, nada instalado ni escrito en código.** 4-nov: Mauro midió
> **0 V en E5-21** (la ECU no tiene crucero) y descarta la ECU nueva y el kit por
> costo: el camino es la **Fase 3**, y su costo está en el § 6. Pedido de Mauro,
> 4-nov-2026: «agregar este proyecto a la Hilux… la ECU de mi camioneta no tiene
> integradas las rutinas del regulador de velocidad… instalé el joystick en el
> volante… incorporarle un mecanismo de control del acelerador en tiempo real…
> o quizás exclusivamente tomar la información del joystick de resistencia
> variable para controlar esta placa de crucero». Y el mismo día, el § 9: «el
> mismo componente Arduino… puede comunicarse con el teléfono de abordo y
> compartir información en tiempo real… algún sensor dedicado dentro del motor
> que nos haga más fuertes y claras las señales que interpreta la app… la
> configuración en tiempo real o aprendizaje de comportamiento».

## 1. Lo que se revisó, y qué es de verdad cada cosa

**`digmorepaka/DBW-Control` (GitHub) existe y se leyó entero** (837 + 168 líneas,
último cambio 30-may-2022, licencia WTFPL). **No es un control crucero.** Es un
controlador de MARIPOSA electrónica independiente: lee el pedal (APP) y mueve el
motor de un cuerpo de mariposa de nafta con un puente H, para motores que no
tienen una ECU que lo haga (swaps, motores de banco). Probado con pedal y
mariposa de Corolla Verso 1ZZ-FE. Lo que hay que saber:

- El autor lo dice en la primera línea: para banco, motor estacionario u
  offroad, **sin garantía**. En su TODO figura «(Off)road test»: nunca anduvo en
  la calle.
- **No tiene lógica de crucero**: ni velocidad del vehículo, ni freno, ni
  embrague, ni botones SET/RES.
- Defectos que se ven leyendo: el control de plausibilidad corre sólo cuando
  `millis() % 200 == 0` (si el bucle tarda, se lo saltea); no hay watchdog;
  `burnCalibration` escribe 38 bytes en un `CRCbuf[37]` (desborde de memoria).
- Lo aprovechable es la IDEA de comparar los dos canales de cada sensor
  (APP1/APP2) y caer a un modo seguro si no coinciden.

**El hilo de EcoModder (`electrical-cruise-control-27176`, «Electrical cruise
control», octubre de 2013)** no se pudo abrir desde acá (503); Mauro pegó el
texto entero el 4-nov. **Tampoco es lo que se describía**: no detalla esquemas
para pedales electrónicos. Es un Golf III de 1994 con acelerador por CABLE: un
Arduino Nano mueve un motor paso a paso que tira del cable, con botones + y −
(control de mariposa CONSTANTE, todavía no de velocidad) y un corte por freno o
embrague. Lo que deja, y vale:
- otro usuario hizo un crucero completo con PID sobre las RPM (no la velocidad):
  si salta una marcha o se aprieta el embrague, las RPM se disparan y el código
  corta en el acto. La idea se lleva bien con el tacómetro que ya oye la app;
- un actuador comercial con embrague magnético: sin corriente, suelta;
- el PID se ajusta por puerto serie con alguien al lado con la computadora;
- y lo único que dice de un acelerador electrónico es un párrafo: intercalar
  el voltaje del pedal (entra el del pie, sale el mismo, y en crucero se queda
  en el último valor), que él mismo llama «riesgoso en el mejor de los casos».
  Es la Fase 3 de abajo, sin ninguno de sus cortes.

**Y la diferencia que decide todo: la Hilux 1KD-FTV es diésel common-rail.** La
potencia no la pone una mariposa: la pone la ECU inyectando más o menos gasoil
según el sensor del pedal. El pedal es «por cable eléctrico»: dos sensores
Hall (VPA y VPA2) que la ECU compara entre sí. **Un crucero acá no mueve nada:
le hace creer a la ECU que el pedal está apretado** (emula VPA/VPA2). DBW-Control
resuelve otro problema y no sirve como base.

## 2. Lo que dicen los dueños de la misma camioneta (KUN26, 1KD-FTV)

Anécdotas de foros, no un manual (ver fuentes): varias ECU de la KUN26 **traen
el crucero adentro** y sólo falta el cableado. El manual de reparación nombra la
señal **CCS (E5-21) contra E1 (E7-7)**: con contacto puesto hay 10–14 V si esa
ECU tiene la función. Quien la retrofiteó tuvo que llevar un cable del clock
spring (detrás del volante) a E5-21, una masa, y conectar el interruptor del
EMBRAGUE (en la manual la ECU lo exige). **Una ECU sin 12 V en E5-21 no tiene la
función**, y ahí las salidas conocidas son cambiar la ECU por una con crucero
(hay que volver a emparejar el inmovilizador) o un **kit comercial «plug and
play» para KUN26 manual** que se intercala en el conector del pedal y trae su
propio corte por freno y embrague.

## 3. Por qué el teléfono NO va en el lazo del acelerador

La app de a bordo es la herramienta equivocada para mandar sobre el motor, y no
por prudencia genérica: este mismo repositorio lo documenta.

- HyperOS mata los servicios en segundo plano (§ MIUI/HyperOS del `CLAUDE.md`):
  un crucero que depende de que Android no cierre la app depende de la suerte.
- El GPS entrega una velocidad por segundo y se cae en túneles y bajo
  parabrisas metalizados; un crucero necesita la velocidad de la rueda, sin
  cortes.
- Un error de la app (ya pasaron: `hasSpeed` mintiendo, el modo Normal mudo)
  hoy da un viaje mal medido; en el acelerador sería otra cosa.

**El acelerador lo manda un aparato dedicado, con cortes por hardware.** La app
puede MOSTRAR lo que hace (activo, velocidad fijada, por qué se cortó) y
REGISTRARLO junto con el viaje, de sólo lectura.

## 4. El plan, por fases (cada una sirve sola)

**Fase 0 · Diagnóstico, sin tocar nada (una tarde, con un tester).**
1. Contacto puesto, motor apagado: tensión entre E5-21 (CCS) y masa en el
   conector de la ECU. Con 10–14 V la ECU tiene crucero; con 0 V, no.
2. El joystick ya instalado: con el tester en el cable que baja del clock spring,
   la resistencia a masa en cada posición (reposo, ON/OFF, SET/−, RES/+,
   CANCEL). Una palanca Toyota manda todo por UN cable, con un valor por botón.
3. Que la luz de freno (STP) y el interruptor de embrague lleguen a la ECU.
4. Anotar el código exacto de la ECU (etiqueta) y el año del vehículo.

**Fase 1 · El camino que recomiendo: el de fábrica o un kit hecho para esta
camioneta.**
- Si E5-21 da 12 V: completar el cableado (palanca → E5-21, masa, embrague) y
  probar. Es el crucero original de Toyota, con todos sus cortes.
- Si da 0 V: (a) una ECU de la misma versión con crucero, emparejada al
  inmovilizador por un taller con Techstream; o (b) un kit comercial para KUN26
  manual, que corta con freno y embrague por su cuenta. Preguntar al proveedor
  si el kit acepta la palanca original como mando.

**Fase 2 · La app sabe que el crucero existe (sólo lectura, sin riesgo).**
Que el viaje registre cuándo estuvo activo y a qué velocidad, para cruzarlo con
el consumo (el crucero bien usado debería bajar los litros cada 100 en ruta) y
con la vibración. La forma más simple: una entrada aislada (optoacoplador) de la
señal «crucero activo» a un microcontrolador chico con Bluetooth que sólo
INFORMA. Nunca al revés.

**Fase 3 · Desarrollo propio (sólo si las fases 1 no son posibles, y empieza en
la mesa, no en la camioneta).** Un emulador de pedal: un microcontrolador entre
el pedal y la ECU que en reposo deja pasar la señal real por relés que, SIN
CORRIENTE, conectan el pedal directo a la ECU. Lo que no se negocia:
- cualquier falla de la placa abre los relés POR HARDWARE y devuelve el pedal
  real; el freno y el embrague apagan el crucero en el programa, y un control
  por cable suelta los relés si la placa no les obedece (§ 9, «Espejo
  permanente», que reemplaza lo que decía acá: que cada frenada soltaba los
  relés);
- nunca entrega menos de lo que pide el pie (el pie siempre gana);
- VPA y VPA2 se emulan con la relación exacta que la ECU espera, o la ECU entra
  en modo de emergencia y graba falla;
- velocidad del sensor de la caja o del tablero, no del GPS;
- watchdog por hardware; se prueba primero con un pedal suelto y la ECU en la
  mesa, después en un lugar cerrado, y recién entonces en ruta.
El joystick se lee ahí: una entrada analógica con divisor, un umbral por botón.

## 5. Lo que hay que decidir (Mauro)

- Hacer la Fase 0 y mandar los cuatro datos (el resto depende de eso).
- Antes de la Fase 3: es una modificación de un mando del vehículo. Puede
  afectar el seguro y la habilitación; conviene preguntar antes de construir.

## 6. Cuánto cuesta la Fase 3 hecha con seguridad (estimación, 4-nov-2026)

Precios aproximados en dólares, de tienda internacional (AliExpress y
similares) y de desarmadero; en Uruguay, comprado en el país, suele ser entre
1,5 y 2 veces más. **A confirmar antes de comprar**, igual que lo que corresponda
pagar al importar.

**La placa (lo que va en la camioneta)**

| Pieza | Para qué | US$ aprox. |
|---|---|---|
| 2 × Arduino Nano (uno de repuesto) | el cerebro; trae watchdog interno | 10–15 |
| DAC doble de 12 bits (MCP4822) + amplificador rail-to-rail (MCP6002) | fabricar VPA y VPA2 limpias, con la relación que espera la ECU | 6–8 |
| 2 relés de señal DPDT de buena marca (Omron G5V-2 o similar) | **sin corriente conectan el pedal real directo a la ECU** | 6–10 |
| Watchdog externo (TPL5010 o un monoestable) + transistores y diodos de los relés | si el programa se cuelga, los relés caen solos | 4–6 |
| 4 optoacopladores (PC817) | freno, embrague, velocidad y contacto, aislados | 2–3 |
| Fuente automotriz 12→5 V de calidad (p. ej. Pololu) + TVS + diodo + portafusible | la camioneta tiene picos de tensión que queman un regulador común | 12–18 |
| Placa impresa, 5 unidades, con envío | se arma una y quedan de repuesto | 15–30 |
| Par de fichas del pedal (macho y hembra) | **intercalar sin cortar un cable**: se saca y la camioneta queda como de fábrica | 15–30 |
| Caja, cable automotriz, terminales, termocontraíble, fusible | | 15–25 |
| LED y zumbador en el tablero, interruptor general | ver y oír cuándo está activo y cuándo cortó | 5–8 |
| **Subtotal placa** | | **90–150** |

**El banco de pruebas (antes de que toque la camioneta)**

| Pieza | Para qué | US$ aprox. |
|---|---|---|
| Pedal usado de 1KD-FTV de desarmadero | probar todo en la mesa con el sensor real | 30–80 |
| Fuente de banco regulable (si no hay una) | simular 12 V, caídas y picos | 30–50 |
| Analizador lógico + osciloscopio de mano o USB | ver las señales que salen hacia la ECU | 50–90 |
| **Subtotal banco** | | **110–220** |

**Total con un 30 % de imprevistos: entre US$ 260 y 480**, de los que unos
US$ 110–200 son herramientas que quedan. El programa, el banco de pruebas de
software y la documentación los escribe Claude: no cuestan plata, cuestan las
pruebas.

**Lo que no se recorta para abaratar**, porque es la seguridad: los relés que
sueltan solos, el watchdog externo, el corte por freno y embrague cableado al
relé (no leído por el programa), la fuente automotriz y las fichas para no
cortar el cableado original.

**Y lo que hay que medir antes de diseñar la placa** (contacto puesto, motor
apagado, tester entre cada señal y la masa del pedal EPA): VPA y VPA2 con el
pedal suelto, a la mitad y a fondo. Con eso se sabe la relación entre las dos
señales que la ECU vigila; si se emula mal, la ECU entra en modo de emergencia.
Además: qué cable del freno da 12 V al pisar (luz de freno), si hay
interruptor de embrague, y de dónde sale la señal de velocidad (en el tablero).

## 7. Sin mesa ni osciloscopio: las pruebas en la camioneta, por etapas (4-nov-2026)

Mauro: no arma mesa de trabajo ni compra osciloscopio; prueba en su propia
camioneta, con las piezas en su lugar y sin instalar del todo hasta que ande.
**Se puede, y el banco del § 6 sale del presupuesto** (queda la placa: con
imprevistos, **US$ 120–200**; opcional, un analizador lógico de US$ 10 y un
módulo Bluetooth de US$ 5 para leer la placa desde el teléfono).

**Por qué el osciloscopio no hace falta:** las dos señales del pedal son
tensiones CONTINUAS que cambian despacio; se miden con el tester. Y el propio
Arduino es el instrumento: lee de vuelta lo que entrega (cada salida va también
a una entrada) y lo manda por cable o Bluetooth, varias veces por segundo, a la
computadora o al teléfono. La velocidad son pulsos que el Arduino cuenta solo.
Lo que un osciloscopio vería (ruido, picos) se cubre con filtros puestos de
entrada en el diseño, y la ECU misma avisa: si no le gusta lo que recibe,
prende la luz del motor y pasa a emergencia. Eso, en las etapas de abajo, es
una señal de prueba y no un accidente.

**El orden de las etapas, y no se saltea ninguna.** Cada una pasa sólo si lo
que se mide con el tester coincide con lo que dice la placa.

1. **Escuchar, motor apagado.** La placa intercalada con las fichas, los relés
   SIN conectar a la salida: sólo lee el pedal, el freno, el embrague y la
   velocidad. Contacto puesto, se aprieta el pedal y se compara con el tester.
2. **Salida al vacío.** La placa fabrica sus dos señales hacia una resistencia,
   no hacia la ECU, copiando el pedal. Tester en la salida.
3. **Paso directo.** Ya conectada a la ECU, relés apagados: el pedal pasa por los
   contactos de reposo. La camioneta tiene que andar EXACTAMENTE igual.
4. **Espejo, parada.** Relés encendidos, la placa copia el pedal (sin crucero).
   Contacto puesto con el motor apagado: la ECU lee y evalúa el pedal sin dar
   potencia, así que si algo está mal se prende la luz y no pasa nada más.
   Después motor en marcha, en punto muerto y con freno de mano: las RPM tienen
   que seguir al pie, sin luz del motor. Acá se prueban las fallas:
   **desenchufar la placa con el motor andando**: el pedal real vuelve solo.
5. **Espejo andando.** Viajes cortos con la placa sólo copiando el pie.
6. **Crucero a baja velocidad, en un lugar vacío**, con otra persona mirando la
   pantalla. Recién después, ruta.

## 8. Lo que enseñan otros casos (búsqueda del 4-nov-2026)

No apareció ningún relato de alguien que haya hecho un crucero casero en una
Hilux 1KD. Sí apareció lo que hacen los productos comerciales en ESTA
camioneta, otros intentos caseros con pedal electrónico y un proyecto abierto
que hace exactamente el intercalado. Lo que se lleva cada uno:

**1. Los kits comerciales para la KUN26 hacen lo mismo que la Fase 3.**
El Autostrada EC-TY13GS (Australia, unos AU$ 880) desenchufa la ficha del pedal
y se intercala con un arnés en T: es un emulador de pedal, no usa el crucero de
la ECU. O sea que **el método está probado en este mismo motor**; lo que cambia
es quién lo garantiza. Lo que exigen esos kits es la lista de requisitos de la
placa:
- **aprender las dos señales del pedal** al instalar (cada pedal es un poco
  distinto: no se escriben valores fijos en el programa);
- **la luz de freno tiene que andar**: si el interruptor o las lamparitas fallan,
  el kit no se activa (la placa tiene que comprobarlo antes de dejar activar);
- **la señal de velocidad** (VSS) es el único cable que no viene en la ficha;
- en la manual, **el interruptor de embrague**.
Ojo: ese kit es para volante a la derecha y el vendedor dice que no sirve para
volante a la izquierda; y vale unas tres veces lo que la placa casera.

**2. Los kits de Mercado Libre Argentina «para Hilux 3.0 2012–2015»** (del orden
de ARS 95.000) son palanca y cableado para una ECU que YA trae el crucero. Con
0 V en E5-21 **no sirven**: no comprar uno de ésos por error.

**3. La 2KD (2.5) no trae crucero en la ECU** según dueños que lo buscaron; la
1KD a veces sí (no la de Mauro). Es la misma conclusión: sin ECU preparada, la
única salida es intercalar el pedal.

**4. El embrague:** un dueño de una 1KD manual 2010 vio que las de fábrica con
crucero traen otro pedalero, con el interruptor de embrague al costado; dobló
una chapa y montó un microinterruptor en el suyo. Si la de Mauro no tiene
interruptor de embrague, ésa es la solución, y además está el corte por RPM
del hilo de EcoModder (§ 1).

**5. Intentos caseros con Arduino (foro de Arduino):**
- el error típico es **P2135** (las dos señales del pedal no se corresponden):
  le pasó a quien cambió el cableado de un pedal emulado. Es la ECU haciendo su
  trabajo; la Fase 4 (contacto puesto, motor apagado) es para verlo sin riesgo;
- **el Arduino no tiene salida analógica**: su «analogWrite» es PWM y hay que
  filtrarlo; por eso la placa lleva un DAC de verdad;
- en algunos pedales una señal sube y la otra baja; en Toyota suelen ir las dos
  subiendo con una diferencia fija (en un 2UZ-FE de Land Cruiser: suelto 0,3–0,9
  V y 1,8–2,7 V; a fondo 3,2–4,8 V y 4,7–5,1 V). **Esos números no son del
  1KD**: se miden en la camioneta;
- y lo que todos repiten: el corte tiene que funcionar el 100 % de las veces,
  por hardware, independiente del programa.

**6. El proyecto abierto que mejor se parece: el «comma pedal»** (comma.ai,
STM32). Se intercala entre el pedal y la ECU, en reposo deja pasar la señal
del pie tal cual y, activo, emula el pedal; **el pie siempre gana** (si el
conductor pide más que el sistema, manda el conductor). Su firmware es público
y es mejor referencia de arquitectura que DBW-Control. Ojo: comma ya no lo
soporta, y el soporte para Toyota depende de la versión.

**7. Lo que cuentan los que lo usan:** no es tan suave como el de fábrica; la
secuencia de aprendizaje se sigue al pie de la letra; y en una camioneta con
poco motor, en subida, el crucero se desactiva solo si no puede sostener la
velocidad (conviene programarlo así: que suelte con aviso en vez de pedir más
y más).

**Lo que cambia en el plan:** nada de fondo, y se suman cuatro requisitos a la
placa: aprender el pedal al instalar, no activarse si la luz de freno no anda,
soltar con aviso si no sostiene la velocidad, y tomar el comma pedal como
referencia del código.

## 9. La placa también le habla al teléfono: sensores dedicados y ajuste en vivo (4-nov-2026)

Pedido de Mauro, el mismo día: «el mismo componente Arduino que instalaremos
para controlar el pedal puede comunicarse con el teléfono de abordo y compartir
información en tiempo real… podría estar aportando la información precisa de
algún sensor dedicado dentro del motor que nos haga más fuertes y claras las
señales que interpreta la app. Además podría permitir la configuración en tiempo
real o aprendizaje de comportamiento a través de las modificaciones o parámetros
que pueda editar el teléfono en tiempo real».

Es la mejor idea del proyecto hasta acá, y hay que decir por qué: **le da a la
app medidas donde hoy tiene deducciones.** Pero son DOS canales distintos y no
se mezclan.

### 9.1 Y conviene darlo vuelta: la placa nace como caja de sensores

La placa de sensores **no toca el pedal**, así que puede existir antes y sirve
sola. Es además la etapa 1 del § 7 —«escuchar, motor apagado»— hecha permanente:
el mismo hardware, el mismo firmware de lectura, sin relés ni salidas. Cuando
esa caja lleve semanas andando y sus números coincidan con el tester, recién
entonces se le agregan las salidas y los relés del crucero. **Se gana valor
desde el primer mes y se llega a la Fase 3 con el hardware ya probado.**

**Y es UN cerebro, no dos** (4-nov-2026). La primera versión de la guía ponía
un ESP32 para los sensores y un Nano aparte para el pedal, para que un cuelgue
del Bluetooth no llegara al acelerador. Mauro lo preguntó el mismo día: «¿por
qué no puede ser uno solo que gestione todo, que en una primera instancia sirva
para registrar las mediciones y en una segunda le demos la activación del
acelerador, con un sistema de seguridad que cuando pierde active el
funcionamiento normal por el relé?». **Puede, y queda así**, porque la
seguridad nunca dependió de cuántos cerebros hay sino de que ninguno pueda
sostener los relés solo. Un ESP32 hace las dos cosas con cuatro condiciones:

1. **Los relés sin corriente conectan el pedal real** y los sueltan tres cosas
   por cable, sin pedirle permiso al programa: el freno, el embrague y el
   watchdog externo.
2. **El programa sólo puede SOLTAR.** Cada vuelta lee de vuelta las dos
   señales que fabrica y las compara con lo que mandó y con la relación
   VPA/VPA2 medida; sólo si todo cierra alimenta al watchdog. Eso cubre lo que
   el watchdog solo no ve: un programa vivo pero equivocado, que era el
   argumento real de los dos cerebros.
3. **El pedal tiene su núcleo**: el ESP32 tiene dos; el lazo del pedal corre
   solo en uno, con prioridad, y el Bluetooth y los sensores en el otro.
4. **Programa nuevo, pruebas de seguridad de nuevo**, aunque el cambio sea de
   un sensor: con un cerebro, tocar los sensores es recargar la placa que
   maneja el pedal. Son diez minutos con la camioneta parada.

Se ahorra el Nano, el cable entre los dos y un segundo programa, y el pedal lee
la velocidad y el freno directo, sin intermediario.

**Espejo permanente: los relés se mueven sólo ante una falla** (4-nov-2026).
Mauro: «el sistema sólo debe entrar en seguridad y desactivar los relés en caso
de una falla. En su funcionamiento normal debemos mantener siempre la
comunicación estable de la ECU por los pulsos emulados por la placa, para
evitar posibles reportes de fallas de la ECU al estar cambiando las señales…
cuando se presiona el freno o el embrague… es la misma placa ESP que envía esa
información… sólo ante una falla de funcionamiento de la placa ESP se deberían
desactivar los relés». Tiene razón, y es lo que hacen los interceptores
comerciales y el de comma (§ 8): **cada conmutación de un relé es un corte de
milisegundos en VPA y VPA2**, y la ECU vigila justamente que esas dos señales
no se corten ni se desacomoden. Si cada frenada mueve los relés, son decenas de
cortes por viaje y tarde o temprano uno se lee como falla.

Así queda:
- **La placa toma el pedal UNA vez, con el motor ya en marcha**, el ralentí
  estable, el pie suelto y cuando ya fabrica exactamente lo que da el pie: el
  arranque, que es cuando la batería baja a 8–9 V, nunca pasa por la placa. Es la única conmutación de un
  viaje normal. Los sensores del pedal siguen alimentados por la ECU (sólo se
  conmutan las dos señales), así que la placa lee el pie todo el tiempo.
- **Desde ahí la ECU lee siempre a la placa**: sin crucero, el pie copiado;
  con crucero, el mayor entre el pie y el crucero.
- **El freno, el embrague y el botón de cancelar apagan el crucero en el
  programa**, en la misma vuelta: la salida vuelve a ser el pie, sin tocar los
  relés.
- **Los relés sueltan sólo ante una falla de la placa**: se cuelga (watchdog),
  lo que fabrica no coincide con lo que tendría que salir (lectura de vuelta),
  o no obedece al freno o al embrague.

**La salvedad, y es la única: ese último control va por cable.** Si el freno
quedara SÓLO en el programa, el caso que importa —un programa vivo pero
equivocado que no suelta el acelerador cuando se frena— dependería del mismo
programa que se equivocó. Por eso un comparador (LM393) mira, mientras el freno
o el embrague están pisados, si la salida de la placa sigue más alta que el pie.
En una frenada normal no hace nada, porque el programa ya volvió a copiar el
pie: no hay conmutación ni corte. Si la placa sigue dando más que el pie por
más de 0,3 s, eso ES una falla de la placa, y el comparador suelta los relés sin
pasar por el programa. Es la regla de Mauro —sólo ante una falla— con la falla
detectada por algo que no es la placa misma.

**La cadena de seguridad: simple, por cable, y sólo para emergencias de
verdad** (4-nov-2026). Mauro: «el diseño debe ponderar sobre todas las cosas la
simpleza y robustez de la propuesta, y un sistema de seguridad debe correr por
encima de todas las herramientas programables para reconectar el sistema
original en caso de emergencia. Pero debe ser verdaderamente un caso de
emergencia que salga del uso esperado».

Todo lo de arriba se reduce a UNA cosa física: la corriente de las bobinas de
los relés pasa por una cadena de contactos en serie —interruptor general,
watchdog, comparador del freno, la orden de la placa—. Cualquier eslabón que
se abra suelta los relés y el pedal original vuelve directo a la ECU. **El
programa puede abrirla, nunca cerrarla solo.** Es el mismo esquema de las
paradas de emergencia industriales, y es fácil de revisar con un tester.

**Lo único que la abre** (lista cerrada, `EMERGENCIAS` de `placa.js`): el
conductor apaga el interruptor; la placa deja de dar señales de vida más de
1,5 s; con el freno o el embrague pisados la placa sigue dando más que el pie
más de 0,3 s; la placa se queda sin corriente; y —la única por programa, que
sólo puede soltar— la placa lee de vuelta lo que fabrica y no cierra varias
vueltas seguidas.

**Lo que NO la abre nunca** (`USO_ESPERADO`): frenar, embragar, cancelar o
volver a poner el crucero, pisar por encima del crucero, dar arranque, prender
luces o aire, una lectura suelta con ruido, perder el Bluetooth. Por eso los
tiempos son holgados, la fuente aguanta el arranque y la placa toma el pedal
con el motor ya en marcha. **Un viaje en el que los relés soltaron sin una
emergencia es un error del diseño a corregir**, no una seguridad que anduvo:
cada soltada es un corte que la ECU puede registrar.

**Y la guía arranca por lo más básico** (4-nov-2026, Mauro: «el proyecto más
básico posible para tener las herramientas que comiencen el aprendizaje de los
instrumentos. Sin intervención»). La caja básica lee SÓLO señales que la
camioneta ya da afuera —la luz de freno (STP), el tacómetro (TACH) y la
velocidad (SPD) del tablero—, con optoacopladores y Posi-Tap, sin cortar un
cable, más su GPS y su acelerómetro. **No toca el pedal**: leer VPA y VPA2 con
el arnés en Y pasó a la etapa del crucero. Y la prueba que manda es que con la
caja puesta las agujas y la luz de freno marquen exactamente lo mismo.

**Las ideas accesorias** (4-nov-2026). Mauro propuso sumarle a la placa un GPS,
un micrófono, que corte el acelerador si falta el teléfono y un rastreador,
«sólo si no amplían o complejizan de forma exagerada el diseño y la
funcionalidad segura». Con ese criterio:

- **GPS propio: entra.** US$ 5–10 y un cable. Da velocidad y posición propias,
  sin depender del teléfono, y **controla** la velocidad de la caja: si la caja
  deja de mandar pulsos, o andando no coincide con el GPS, el crucero se apaga
  como con el botón de cancelar (suave, sin relés). No es la velocidad del
  crucero: da de 1 a 10 lecturas por segundo y se corta en un túnel.
- **RPM exactas: del cable del tacómetro, no de un micrófono.** En el vano del
  motor hay más de 100 °C, agua y un cable que cruza el parallamas, y oír las
  RPM es justo lo que hoy confunde la 2.ª con la 4.ª. El acelerómetro de la
  placa queda como segunda opinión.
- **Todo lo que mide la placa es suyo**: va marcado como de la placa, no se
  mezcla con lo del teléfono y no se presenta como dato de la ECU.
- **Cortar el acelerador si falta el teléfono: no.** Que falte el teléfono es
  uso esperado; si moviera los relés, cada corte de Bluetooth sería un corte en
  las señales de la ECU y la seguridad dependería del teléfono. Queda como
  opción a decidir que sin teléfono el crucero no se pueda poner (suave).
- **Rastreador: no.** Avisar dónde está la camioneta necesita una línea móvil
  con abono mensual, y un rastreador contra robo tiene que tener batería propia
  y estar escondido: es otro aparato. Gratis queda que la placa guarde sus
  últimas posiciones y el teléfono las lea al conectarse.

**La guía paso a paso está en el panel**: `placa.html` de
`maurogasta-crypto/datos` (Sitios → SITD-Hilux → «🔧 Armar la placa»), con las
compras, el armado, las pruebas y lo que se va marcando. Su contenido vive en
`placa.js` de ese repositorio: **si cambia este archivo, cambia aquél en la
misma tanda.**

### 9.2 Lo que la app gana con cada sensor (en orden de lo que más destraba)

| Sensor | Hoy | Con la placa |
|---|---|---|
| **RPM del motor** | se OYEN con el micrófono: errores de octava, la 2.ª contra la 4.ª, y abajo de 30 km/h no se oye nada (`regimen.dart`, `tacometro.dart`) | un pulso por inyección o por diente del cigüeñal, contado por el Arduino: RPM exactas, siempre, también parado |
| **Velocidad (VSS de la caja)** | GPS: una por segundo, se cae en túneles y bajo parabrisas metalizado | pulsos contados, sin cortes. Y con RPM + velocidad **la marcha se CALCULA** en vez de deducirse: cierra el problema de la 2.ª/4.ª y `hilux:E2` |
| **Acelerómetro en un punto rígido** | el del teléfono entrega 200 Hz, o sea que arriba de 100 Hz todo se pliega; los rodamientos **no se ven** | un acelerómetro propio a 1–2 kHz sube el techo a 500 Hz o más: rodamientos, cardán a cualquier velocidad y el encendido sin plegarse |
| **Posición del pedal** | no se mide | es la CARGA, que es justo lo que le falta a la línea base para separar «camino áspero» de «motor haciendo fuerza» |
| **Temperatura de refrigerante y de admisión** | no se mide | un motor frío vibra y suena distinto: hoy eso entra como ruido en las cubetas |

**La forma de entrar a la app ya está escrita y no hay que inventarla:** el GPS
entra por `FuenteDeMuestras` y el régimen por `FuenteDeRegimen`
(`CLAUDE.md`, «El GPS entra por una interfaz, igual que va a entrar el OBD2»).
La placa es otra implementación de esas interfaces, por Bluetooth. El motor de
análisis no tiene que saber de dónde salen los números.

**Y rige la regla de siempre: la frecuencia de muestreo que se guarda es la
MEDIDA, no la pedida**, y las ventanas de la placa son **otra clase de
muestreo** —como los 50 y los 200 Hz de `sitd-42`—: no se comparan con las
viejas, y la línea base vuelve a aprender desde cero. Lo que no se borra sigue
contando si la placa se desconecta.

### 9.3 El otro canal: lo que el teléfono le puede editar, y lo que no

Acá hay que ser preciso, porque «configuración en tiempo real» puede querer
decir dos cosas muy distintas:

- **Sí: los parámetros de MEDIDA y de confort.** Cada cuánto manda cada señal,
  qué filtros usa, cuántos pulsos por vuelta tiene la rueda o la caja, la
  relación de cada marcha, los umbrales con los que la app pide grabar 10 s, y
  —con el crucero ya andando— la suavidad con la que persigue la velocidad
  (las constantes del PID). Eso es exactamente lo que el hilo de EcoModder
  ajustaba por puerto serie con alguien al lado con la computadora; hacerlo
  desde el teléfono es mejor y es lo que pide Mauro.
- **No: los límites de seguridad.** Cuánta autoridad tiene la placa sobre el
  pedal, los cortes por freno y embrague, el tiempo del watchdog, el «el pie
  siempre gana» y los relés que sin corriente devuelven el pedal real. Eso vive
  en el firmware y en el hardware, y **no hay un mensaje que lo cambie**: si
  existiera, el teléfono estaría otra vez en el lazo del acelerador y se cae el
  § 3 entero.

Y tres condiciones para cada cambio, que son las que lo hacen seguro:

1. **Un parámetro se acepta sólo con el crucero apagado** (y los que cambian el
   control, además con el vehículo detenido). Un cambio que llega a mitad de
   una curva no se aplica.
2. **El firmware recorta.** Cada parámetro tiene su rango clavado en el código;
   lo que llega afuera de rango se descarta y se avisa. Un teléfono con un
   error de dedo no puede pedir algo imposible.
3. **Queda escrito de los dos lados.** La placa anota qué cambió y cuándo, y la
   app lo guarda con el viaje: un número que se tocó y nadie anotó convierte
   todos los viajes siguientes en incomparables.

### 9.4 El aprendizaje queda en el teléfono, y no es una concesión

La placa tiene que ser rápida y tonta; el teléfono tiene la historia, el SQLite,
los respaldos y la nube. Así que **el aprendizaje sigue donde ya está** —la
línea base por cubeta, el factor de neumáticos, el tacómetro— y lo nuevo es
que el teléfono puede **proponerle a la placa** un parámetro mejor. Es el mismo
reparto de siempre en este ecosistema: el que aprende propone, el que manda
decide, y el que decide es el que tiene los cortes por hardware.

**Cupo: cero.** Es Bluetooth entre dos aparatos que están en la misma cabina;
no toca la red ni ninguna base. El módulo son los US$ 5 que ya figuran en el
§ 6, más unos US$ 10 del acelerómetro dedicado.

## Fuentes

- https://www.allfourx4.com.au/Cruise-Control-Kit-Plug-Play-suitable-for-Hilux-KUN-D4D-3Ltr-EC-TY13GS (kit para KUN 1KD, intercalado en el pedal)
- https://www.conrad-anderson.co.uk/product/toyota-hilux-2005-2016-aftermarket-cruise-control-kit/ (aprendizaje del pedal y control del freno)
- https://www.4x4community.co.za/forum/showthread.php/114242-Aftermarket-Cruise-control-for-Hilux-Fortuner
- https://www.hilux4x4.co.za/views/viewtopic.php?t=20207 (programación, freno, embrague y VSS)
- https://www.newhilux.net/phpbb/viewtopic.php?f=11&t=2542&start=140 (2KD sin crucero; microinterruptor de embrague)
- https://forum.arduino.cc/t/cruise-control-with-the-arduino/465070
- https://forum.arduino.cc/t/reading-a-cars-accelerator-pedal-position-sensors-and-sending-them-to-two-ecus/605050 (P2135)
- https://lc100e.github.io/pdf/rm/rm630e/m_di_0079.pdf (valores de VPA/VPA2 de otro motor Toyota)
- https://community.sunnypilot.ai/t/3741 (gas interceptor: el pie siempre gana)
- https://listado.mercadolibre.com.ar/kit-control-velocidad-crucero-toyota-hilux

- https://github.com/digmorepaka/DBW-Control (leído entero el 4-nov-2026)
- https://www.newhilux.net/phpbb/viewtopic.php?t=30088 (retrofit, E5-21, embrague)
- https://www.newhilux.net/phpbb/viewtopic.php?p=419239 (cambio de ECU para tener crucero)
- https://www.allfourx4.com.au/Cruise-Control-Kit-Plug-n-Play-suitable-for-Hilux-KUN26-Manual-05-15-EC-TY13GS-3/ (kit para KUN26 manual 2005–2015)
- https://ecomodder.com/forum/showthread.php/electrical-cruise-control-27176.html (texto pegado por Mauro el 4-nov: 9 mensajes, oct-2013)
