# Etapas y cambios (14-nov-2026)

Este documento explica **qué cambió** en `PLACA-FASE-1.md`, `CRUCERO.md` y el
índice de `CLAUDE.md` desde la última versión, **qué se identificó** de la
camioneta y de las piezas, y **qué etapas se están pensando** para la placa.
Casi todo lo de acá es **propuesta o reflexión, no decisión tomada**: lo marcado
como medido o confirmado lo dice expresamente.

## 1. Lo que se identificó (con fotos en `fotos/`)

| Qué | Dato | Fuente | Estado |
|---|---|---|---|
| Placa del chasis | KUN36L-PRMSYG · 1KD-FTV 2982 cc · chasis 8AJEZ39G802513562 · caja R151-B04B · planta 8AJ · color 1C0 · trim GZ (o G2) | `fotos/placa-chasis-KUN36L.jpg` | leído de la foto |
| Libreta | HILUX SRV TDI **4X2** · año **2008** · cab. doble · 3000 cc · P.B.T. 2800 kg · motor 1KD-7463163 · mismo chasis que la placa | `fotos/libreta-datos-tecnicos.jpg` (recorte; no se guardó nombre, documento, matrícula ni padrón) | leído de la foto |
| ECU | TOYOTA 89661-0K300 · MA175800-6625 · DENSO · Malasia | `fotos/ecu-89661-0K300.jpg` | etiqueta |
| Pedal | TOYOTA 78120-0K010 · VN198800-3140 · 5,0 V · DENSO · Vietnam (más «314» y «10 J22», sin interpretar) | `fotos/pedal-78120-0K010.jpg` | etiqueta |
| ESP32 | módulo ESP-32 Wi-Fi + Bluetooth en placa de borneras, chip USB CP2102, USB-C | foto del 13-nov | a la vista |
| Módulo de optos | «4 Channel Isolation / 817 Module», un jumper por canal | foto del 13-nov | a la vista; falta probarlo |
| Otros | capacitor 10 000 µF / 16 V; bolsa de diodos (marcado **ilegible**) | foto del 13-nov | a la vista |

**Desacuerdos que quedan abiertos** (no se resolvieron; no se tocó ninguna
constante de la app):

- **¿4x2 o 4x4?** La libreta dice 4X2. Por la numeración habitual de Toyota el
  «36» sería 4x4, y la caja R151 también lo sugiere (**inferencia**, no hay una
  fuente que lo diga). Se verifica mirando si tiene palanca o botón de doble
  tracción y cardán delantero. Importa para el análisis de vibración.
- **¿Caja R151 o R150F?** `CLAUDE.md` calcula las marchas con una R150F
  (3,830 · 2,062 · 1,436 · 1 · 0,838, diferencial 3,583); la placa dice R151 y un
  código de eje B04B cuya relación no se conoce.
- **Neumáticos:** el catálogo da 265/70R16 para esa versión; el proyecto usa
  265/70R17. Se mira la medida impresa en la cubierta.
- **SRV vs SR:** la libreta dice SRV y el catálogo da SR. Puede ser
  nomenclatura distinta; no se resolvió.
- **El manual de reparación usado** (Hilux Repair Manual, Argentina, DR201E,
  para 1KD-FTV / 2KD-FTV) **no se verificó que cubra la KUN36L** ni que
  corresponda a la ECU 0K300.
- **Kits de crucero:** `CRUCERO.md` habla de KUN26; la camioneta es KUN36L. Antes
  de comprar un kit, preguntar al proveedor.

## 2. Qué cambió en cada archivo

**`PLACA-FASE-1.md`**

- § 3: las piezas que Mauro ya tiene (ESP32, módulo de optos, capacitor, diodos,
  diez resistencias de 10 kΩ), qué falta comprar y que la compra de los
  divisores queda **a revisar**.
- § 4.1: **par alternativo de divisores 56 kΩ + 82 kΩ** (0,594) por si no hay de
  100 kΩ. La corriente de falla sube de ≈ 75 a ≈ 89 µA; lo importante es que las
  cuatro tomas usen el mismo par.
- § 4.2 bis (nuevo): identificación de la camioneta, la ECU, el pedal y la
  libreta; glosario de los seis cables del pedal (A13 ↔ E5, colores, tensiones,
  códigos de falla); procedimiento de identificación con el tester; fotos.
- § 4.2 bis, nota: sin ADS1115, EPA y EPA2 casi no valen nada leídas con el ADC
  interno.
- § 4.6: **la regla «ninguna salida» se amplía:** además del LED y el CS de la
  microSD, hay un **buzzer en el banco de pruebas del mando**, que no se conecta
  a nada del vehículo.
- § 4.7 (nuevo): banco de pruebas del joystick con buzzer, con los valores de
  referencia de la palanca, por qué el pull-up debe ser de ~1 kΩ y no de 10 kΩ,
  cómo detectar un cable cortado, reglas del firmware y pruebas contra falsos
  positivos.
- § 4.8 (nuevo): primera lectura del pedal con el ADC interno, con sus
  limitaciones.
- § 8: etapas 0 bis y 0 ter (banco del mando y módulo de optos en la mesa).
- § 10 y «Fuentes»: pendientes nuevos y de dónde sale cada valor.

**`CRUCERO.md`**

- Aviso en el § 2: la camioneta es KUN36L, no KUN26.
- Fase 0: el paso 4 se marca como hecho (ECU y chasis; año 2008 por la libreta).
- Fase 0, paso 2 y fin del § 4: valores de referencia de la palanca y la prueba
  con buzzer antes de dejarla mandar algo.
- Una fuente nueva.

**`CLAUDE.md`:** una fila nueva en el índice de documentos, para este archivo.

**No se tocó** ninguna constante de la app (relaciones de caja, neumático,
diferencial).

## 3. Las etapas que se están pensando

Cada una sirve sola, y la siguiente sólo se hace si la anterior salió bien.

| Etapa | Qué es | Qué hace falta | Qué se aprende | Para pasar a la siguiente |
|---|---|---|---|---|
| **A · Mesa** | ESP32 por USB con un firmware de prueba por BLE; módulo de optos con 12 V y un pulsador | lo que ya tiene Mauro | qué lado del módulo es la entrada, qué hace el jumper, que el teléfono ve los datos | el módulo se comporta como se espera |
| **B · Banco del mando con buzzer** | resistencias fijas (≈ 220 Ω, 680 Ω, 1,5 kΩ) en lugar de la palanca; calibrar bandas, filtro y alarma de falla | resistencias de 1 kΩ y 4,7 kΩ, 220 Ω/680 Ω/1,5 kΩ, buzzer activo 5 V, 100 nF, 4 pulsadores | si la lectura distingue cada botón y detecta fallas | ningún falso positivo en la mesa |
| **C · Mando real, sin tocar la camioneta** | la palanca instalada, leída en el ESP32 con el buzzer | el valor medido con el tester en cada botón | si el resorte del volante, el ruido y los baches generan órdenes falsas | **cero eventos falsos en varias horas** (el número se fija) |
| **D · Contexto en la camioneta** | freno (STP), tacómetro (TACH), velocidad (SPD) y contacto por los optoacopladores | tester y fichas reversibles; identificar los cables antes de pelar | forma y frecuencia de las señales; cuántos pulsos por vuelta | las señales son limpias y la camioneta anda igual |
| **E · Pedal exploratorio (ADC interno)** | VPA y VPA2 con divisores, leídos por el ESP32; EPA/EPA2 con el tester | 8 resistencias de divisor (≈ 10 de cada valor), 100 nF | la forma de las curvas y la relación entre VPA y VPA2 | las curvas coinciden con el tester y la ECU no marca falla |
| **F · Pedal con calidad** | ADS1115 con lectura diferencial; acelerómetro; microSD | ADS1115 (opcional), acelerómetro, microSD | precisión para el análisis | decide si vale la pena según lo visto en E |
| **G · Control (Fase 3 de `CRUCERO.md`)** | emular el pedal para el crucero | seguro, DAC, relés, y toda la seguridad de `CRUCERO.md` | — | **no es parte de este documento**; hay que consultar al seguro antes |

**Lo que cada lectura puede reorientar** (preguntas que se contestan con las etapas D y E):

- ¿VPA y VPA2 mantienen la relación que dice el manual (VPA2 unos 0,8 V arriba al
  soltar)? Eso decide si emular el pedal es viable.
- ¿Qué frecuencia dan TACH y SPD, y con qué forma de onda?
- ¿El ADC interno alcanza, o hace falta el ADS1115?
- ¿La ECU nota la placa? (luz del motor, códigos de falla como P2120, P2125,
  P2138)

## 4. Decisiones de diseño y su razón

- **Divisores:** el ESP32 tolera 3,3 V y el pedal da hasta 5. Una resistencia
  de decenas de kΩ pegada al punto de toma carga muy poco al pedal y limita la
  corriente si el cable se corta o se pone en corto. Hay que usar cuatro, uno por
  señal y por masa.
- **Alta impedancia, no precisión, es lo que protege a la ECU.** La precisión del
  ADC sirve para analizar mejor y, más adelante, para una salida; no es lo que
  evita interferir con la ECU. (Corrección de una explicación anterior que había
  exagerado la importancia de la precisión.)
- **ADS1115:** ADC externo de 16 bits por I2C, con entradas diferenciales. Es
  opcional para empezar; se decide después de la etapa E.
- **Joystick:** el pull-up tiene que ser del orden de 1 kΩ (con 10 kΩ las lecturas
  caen en la zona donde el ADC lee mal). **Antes** de que mande algo, se prueba
  con un buzzer (etapas B y C).
- **Buzzer:** pasa a ser una salida más, **sólo en el banco de pruebas**.

## 5. Pendientes y dudas abiertas

| # | Pendiente | Quién |
|---|---|---|
| 1 | Qué dicen los diodos de la bolsa (para qué sirven) | Mauro: foto o texto |
| 2 | Resistencia de cada botón del joystick, medida con el tester | Mauro |
| 3 | Cuál par de divisores se compra y con qué tolerancia | **a revisar más adelante** |
| 4 | Si MakerHero envía a Uruguay (no se pudo confirmar) | Mauro: preguntarles antes de pagar |
| 5 | 4x2 o 4x4; caja R151 o R150F; neumático real | Mauro: mirar la camioneta |
| 6 | Si el manual DR201E vale para la KUN36L y la ECU 0K300 | se confirma con el tester |
| 7 | Cables de colores en la foto de la ECU y arnés sin forro en la del pedal: si son de una intervención anterior, anotar adónde va cada uno | Mauro |
| 8 | Si el repositorio es público: no hay nombre, documento ni matrícula en lo que se guardó, pero **sí están los números de chasis y de motor** | Mauro decide |

## 6. Lista de compra provisoria (tienda MakerHero, en portugués)

Sin precios verificados salvo los que mostró la tienda (R$ 0,09 por resistencia).
**La de 100 kΩ estaba agotada.** Los valores de 1 % no estaban disponibles; la
ficha del 68 kΩ decía ±1 %, y para 56 kΩ y 82 kΩ **no se confirmó la tolerancia**.
La compra se revisa más adelante.

| Pieza | Cantidad | Nota |
|---|---|---|
| Resistor 56 kΩ 1/4W | 10 | divisor (necesitás 4) |
| Resistor 82 kΩ 1/4W | 10 | divisor (necesitás 4) |
| Resistor 2 kΩ 1/4W | 10 | pull-up del joystick (ideal 1 kΩ; dos de 2 kΩ en paralelo dan 1 kΩ) |
| Resistor 4,7 kΩ 1/4W | 5 | fin de línea |
| Resistor 220 Ω, 680 Ω y 1,5 kΩ | 2 de cada | para simular la palanca |
| Capacitor cerâmico 100 nF (código 104) | 10 | filtro |
| Buzzer ativo 5 V (de preferencia en módulo con transistor) | 2 | si es suelto, agregar un NPN BC547 o 2N2222 |
| Chave tátil (push button) | 4 | |
| Fio flexível 24 AWG y tubo termorretrátil | ≈ 5 m | |
| Agulhas de prova finas | — | medir por atrás del conector |
| Módulo ADS1115 | 1 | **opcional** |

Ya tiene: ESP32 con borneras, módulo de 4 optoacopladores, capacitor de
10 000 µF, 10 resistencias de 10 kΩ y los diodos.

## 7. Qué no se verificó

- Ningún valor eléctrico de este documento está **medido en la camioneta**: salen
  de manuales de otros modelos o de la misma familia, de foros y de cálculos.
- Los valores de la palanca de crucero son de otra Hilux (posiblemente más
  nueva) y de un Corolla; los de un Land Cruiser son otros.
- No se verificó que la tienda envíe a Uruguay ni los precios finales.
- La lectura de las fotos puede tener errores (por ejemplo el trim «GZ»/«G2» y el
  rayón en el número de chasis, que coincide con la libreta).
