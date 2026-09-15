# SITD-Hilux

Telemetría, odometría y diagnóstico mecánico para una **Toyota Hilux 3.0**
(1KD-FTV, 2008-2011). Android, sin conexión, sin servidor, sin cuenta de nadie.

> **Estado: tanda 1 — el esqueleto.** Todavía no mide nada. Lo que hay es la
> base local con sus migraciones, la lógica de odometría con su banco de
> pruebas, y el camino que lleva el APK desde un push hasta el teléfono. La
> odometría en vivo llega en la tanda 2.

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

## Mapa de archivos

```
lib/
├── core/
│   ├── db/
│   │   ├── esquema.dart     SQL y migraciones. Una migración publicada
│   │   │                    NO se edita: se agrega otra abajo.
│   │   └── base.dart        Apertura, WAL, migración, ajustes.
│   └── version.dart         Sellos, a la vista en la barra.
├── features/
│   └── odometro/
│       ├── muestra.dart     La lectura del GPS y el par de calibración.
│       ├── integrador.dart  Distancia por velocidad Doppler.
│       └── factor.dart      Corrección del odómetro de fábrica.
└── main.dart                Pantalla de arranque: ¿la cadena funciona?

test/                        41 casos. Corren sin emulador ni teléfono.
.github/workflows/apk.yml    Verificación previa + APK + release.
```

## Sellos de versión

| Archivo | Sello | Dónde |
|---|---|---|
| Aplicación | `sitd-1` | `lib/core/version.dart` |
| Esquema de la base | `1` | `lib/core/db/esquema.dart` |

Ante una discrepancia entre esta tabla y el sello escrito adentro del archivo,
**manda el archivo**: esta tabla se copia a mano y se desactualiza en silencio.

## Verificación previa

No es opcional. Es exactamente lo que corre el workflow, y si falla, no se
sube:

```bash
flutter analyze --fatal-infos --fatal-warnings
dart format --output=none --set-exit-if-changed .
flutter test
```

## Las dos cosas que sorprenden

**La distancia no se calcula sumando distancias.** Se integra la velocidad que
informa el receptor GPS, que sale del corrimiento Doppler de la portadora y
tiene un error de ~0,1 m/s. Sumar haversines entre posiciones consecutivas
parece lo obvio y es el error clásico: el ruido de posición siempre suma y
nunca resta, así que una camioneta detenida acumula kilómetros. Hay una prueba
dedicada a ese caso (`DETENIDO con ruido de GPS no acumula un metro`), y
comprueba las dos mitades: que la integración da cero y que el haversine da más
de cien metros.

**El factor de neumáticos corrige al tablero, no al GPS.** El GPS ya mide la
distancia real. El que miente es el odómetro de fábrica, que cuenta vueltas de
rueda y las multiplica por la circunferencia que traía. Entonces
`km_real = km_tablero × k`, y `k` no se teclea: se aprende de la mediana de los
cocientes de los tramos largos.

## Requisitos de desarrollo

Flutter 3.47.4, JDK 17, SDK de Android. `minSdk` es **29** (Android 10) porque
el teléfono de destino es un Redmi Note 9, no el Redmi 15 con el que se
desarrolla.

## Reglas del repositorio

En `CLAUDE.md`, incluido por qué este proyecto rompe la regla de «se edita
desde el teléfono» que siguen los otros cuatro del ecosistema.
