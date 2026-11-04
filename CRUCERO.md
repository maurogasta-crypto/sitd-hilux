# Control crucero para la Hilux — plan

> Estado: **plan, nada instalado ni escrito en código.** 4-nov: Mauro midió
> **0 V en E5-21** (la ECU no tiene crucero) y descarta la ECU nueva y el kit por
> costo: el camino es la **Fase 3**, y su costo está en el § 6. Pedido de Mauro,
> 4-nov-2026: «agregar este proyecto a la Hilux… la ECU de mi camioneta no tiene
> integradas las rutinas del regulador de velocidad… instalé el joystick en el
> volante… incorporarle un mecanismo de control del acelerador en tiempo real…
> o quizás exclusivamente tomar la información del joystick de resistencia
> variable para controlar esta placa de crucero».

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
- freno, embrague y cualquier falla abren los relés POR HARDWARE (no por
  software) y devuelven el pedal real;
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

## Fuentes

- https://github.com/digmorepaka/DBW-Control (leído entero el 4-nov-2026)
- https://www.newhilux.net/phpbb/viewtopic.php?t=30088 (retrofit, E5-21, embrague)
- https://www.newhilux.net/phpbb/viewtopic.php?p=419239 (cambio de ECU para tener crucero)
- https://www.allfourx4.com.au/Cruise-Control-Kit-Plug-n-Play-suitable-for-Hilux-KUN26-Manual-05-15-EC-TY13GS-3/ (kit para KUN26 manual 2005–2015)
- https://ecomodder.com/forum/showthread.php/electrical-cruise-control-27176.html (texto pegado por Mauro el 4-nov: 9 mensajes, oct-2013)
