# SITD-Hilux

Telemetría, odometría y diagnóstico mecánico para una **Toyota Hilux 3.0**
(1KD-FTV, 2008-2011). Android, sin conexión, sin servidor, sin cuenta de nadie.

> **Estado: tanda 2 — la odometría en vivo.** Ya mide. Se abre un viaje, el GPS
> entrega una muestra por segundo, la distancia se integra de la velocidad
> Doppler y cada muestra cruda queda guardada en el teléfono. Lo que falta es
> el combustible (tanda 3), el acelerómetro (4) y el micrófono (5).

## Instalar en el teléfono

1. Entrar a la pestaña **Releases** del repositorio, release **`ultimo`**.
2. Tocar el archivo `sitd-hilux-NN.apk`.
3. Android va a pedir permiso para instalar desde el navegador. Se le da.

El release se reemplaza en cada push a `main`, así que ese enlace siempre
apunta a lo último. Los APK de tandas anteriores quedan como *artifacts* de
cada corrida en la pestaña **Actions**.

**Si falla la instalación diciendo que hay un conflicto**, es porque la versión
instalada se firmó con otra clave de depuración. Se desinstala la vieja y se
instala de nuevo. No pasa una vez que está andando.

## Cómo se usa

Una pantalla, tres botones y ningún menú:

| | |
|---|---|
| **Empezar el viaje** | pide el permiso de ubicación —la primera vez— y abre un viaje |
| **Pausar** | suelta el GPS sin cerrar el viaje. Para una parada larga |
| **Terminar** | cierra el viaje y deja el total escrito |

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
│       ├── registro.dart    Viajes y puntos en la base.
│       └── servicio.dart    Junta las tres piezas y sostiene el viaje.
├── ui/
│   ├── formato.dart         Cómo se escribe un número para leerlo.
│   ├── pantalla_viaje.dart  La pantalla del viaje en curso.
│   └── pantalla_diagnostico.dart  ¿Esto anda? y los últimos viajes.
└── main.dart                Abre la base y dibuja.

test/                        83 casos. Corren sin emulador ni teléfono.
.github/workflows/apk.yml    Verificación previa + APK + release.
```

## Sellos de versión

| Archivo | Sello | Dónde |
|---|---|---|
| Aplicación | `sitd-2` | `lib/core/version.dart` |
| Esquema de la base | `1` | `lib/core/db/esquema.dart` |

Ante una discrepancia entre esta tabla y el sello escrito adentro del archivo,
**manda el archivo**: esta tabla se copia a mano y se desactualiza en silencio.

La tanda 2 **no** toca el esquema: las tablas `viajes` y `puntos` ya estaban
creadas desde la migración 0 → 1. Recién ahora se llenan.

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
