# SITD-Hilux

Telemetría, odometría y diagnóstico mecánico para una **Toyota Hilux 3.0**
(1KD-FTV, 2008-2011). Android, sin conexión, sin servidor, sin cuenta de nadie.

> **Estado: tanda 4 — combustible.** Ya mide. Se abre un viaje, el GPS
> entrega una muestra por segundo, la distancia se integra de la velocidad
> Doppler y cada muestra cruda queda guardada en el teléfono. Y ya lleva las
> cargas de combustible, con el consumo y el factor de neumáticos calculados
> al leer. Lo que falta es el acelerómetro y el micrófono.

## Instalar en el teléfono

Desde el navegador del teléfono, no desde la aplicación de GitHub:

1. Entrar a
   [releases/tag/ultimo](https://github.com/maurogasta-crypto/sitd-hilux/releases/tag/ultimo)
   y tocar el archivo `sitd-hilux-NN.apk`.
2. Al abrir lo descargado, Android dice que no puede instalar apps desconocidas
   de esa fuente. En ese mismo cartel: **Ajustes → Permitir desde esta fuente →
   Atrás**. Es una sola vez.
3. **En Xiaomi hay dos pasos más**, y los dos asustan sin motivo: aparece
   «Analizando la app…» y después un cartel de que no es de confianza →
   **Instalar de todos modos**. Si insiste, en **Seguridad → Ajustes → Analizar
   apps antes de instalar** se apaga mientras se instala.

Desconfía porque el APK está firmado con la clave de depuración, no con una de
Play Store. Es la nuestra: la compila el workflow de este repositorio.

El release se reemplaza en cada push a `main`, así que ese enlace siempre
apunta a lo último. Los APK de tandas anteriores quedan como *artifacts* de
cada corrida en la pestaña **Actions**.

**Si falla la instalación diciendo que hay un conflicto**, es porque la versión
instalada se firmó con otra clave de depuración. Se desinstala la vieja y se
instala de nuevo. No pasa una vez que está andando.

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

El icono del surtidor, arriba, lleva a **Combustible**: ahí se anota cada
carga —litros, odómetro del tablero, costo, si quedó lleno— y se ven el
consumo, el costo por kilómetro y el factor de neumáticos. Nada de eso se
guarda calculado: sale de las cargas cada vez que se abre la pantalla.

Arriba, los kilómetros en grande y la velocidad. Abajo, lo que hay que mirar
cuando algo no cuadra: muestras usadas, descartadas, **sin velocidad**, cortes,
el haversine de control y la discrepancia entre los dos métodos. El icono de
información de la barra lleva al estado de la aplicación y a los últimos
viajes.

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
│   └── version.dart         Sellos, a la vista en «Estado».
├── features/
│   └── odometro/
│       ├── muestra.dart     La lectura del GPS y el par de calibración.
│       ├── integrador.dart  Distancia por velocidad Doppler: `integrar`
│       │                    para una lista y `Acumulador` para el vivo.
│       ├── factor.dart      Corrección del odómetro de fábrica.
│       ├── fuente.dart      La interfaz del GPS, y por qué es una interfaz.
│       ├── fuente_gps.dart  El GPS real, con el servicio en primer plano.
│       ├── registro.dart    Viajes, puntos y los pares de calibración.
│       └── servicio.dart    Junta las tres piezas y sostiene el viaje.
│   └── combustible/
│       ├── carga.dart       Una carga, tal como se teclea en la estación.
│       ├── consumo.dart     Consumo de lleno a lleno, calculado al leer.
│       └── registro_cargas.dart  Cargas y el ajuste del tanque.
├── ui/
│   ├── formato.dart         Cómo se escribe un número para leerlo.
│   ├── pantalla_viaje.dart  La pantalla del viaje en curso.
│   ├── pantalla_combustible.dart  Consumo, factor y las cargas.
│   ├── pantalla_carga.dart  El formulario, para llenar al lado del surtidor.
│   └── pantalla_diagnostico.dart  ¿Esto anda? y los últimos viajes.
└── main.dart                Abre la base y dibuja.

test/                        124 casos. Corren sin emulador ni teléfono.
.github/workflows/apk.yml    Verificación previa + APK + release.
```

## Sellos de versión

| Archivo | Sello | Dónde |
|---|---|---|
| Aplicación | `sitd-4` | `lib/core/version.dart` |
| Esquema de la base | `1` | `lib/core/db/esquema.dart` |

Ante una discrepancia entre esta tabla y el sello escrito adentro del archivo,
**manda el archivo**: esta tabla se copia a mano y se desactualiza en silencio.

Ninguna tanda tocó el esquema todavía: `viajes`, `puntos`, `cargas` y
`ajustes` están las cuatro desde la migración 0 → 1. Se fueron llenando.

## Verificación previa

No es opcional. Es exactamente lo que corre el workflow, y si falla, no se
sube:

```bash
flutter analyze --fatal-infos --fatal-warnings
dart format --output=none --set-exit-if-changed .
flutter test
```

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

Dependencias, y son tres: `sqlite3` (base local, sin generación de código),
`geolocator` (GPS y servicio en primer plano) y `path_provider` (dónde va el
archivo de la base).

## Reglas del repositorio

En `CLAUDE.md`, incluido por qué este proyecto rompe la regla de «se edita
desde el teléfono» que siguen los otros cuatro del ecosistema.
