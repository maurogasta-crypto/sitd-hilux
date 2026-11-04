# Control crucero para la Hilux — plan

> Estado: **plan, nada instalado ni escrito en código.** Pedido de Mauro,
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

**El hilo de EcoModder (`electrical-cruise-control-27176`) no se pudo leer**: el
sitio cortó la conexión y después contestó 503, y no apareció en búsquedas.
Hasta leerlo, no se usa como fuente.

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

## Fuentes

- https://github.com/digmorepaka/DBW-Control (leído entero el 4-nov-2026)
- https://www.newhilux.net/phpbb/viewtopic.php?t=30088 (retrofit, E5-21, embrague)
- https://www.newhilux.net/phpbb/viewtopic.php?p=419239 (cambio de ECU para tener crucero)
- https://www.allfourx4.com.au/Cruise-Control-Kit-Plug-n-Play-suitable-for-Hilux-KUN26-Manual-05-15-EC-TY13GS-3/ (kit para KUN26 manual 2005–2015)
- https://ecomodder.com/forum/showthread.php/electrical-cruise-control-27176.html (no se pudo leer: 503)
