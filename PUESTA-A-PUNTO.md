# Dejar de desinstalar en cada tanda — paso a paso

**Para hacer todo desde el teléfono.** No hace falta una computadora.

Hoy cada actualización de la aplicación obliga a **desinstalar**, y desinstalar
**borra la base**: los viajes, la configuración de la nube y el modo de GPS que
la aplicación había aprendido. Esta guía lo termina.

> **El orden importa y no es un detalle.** Si hacés el paso 2 antes del 1, sale
> otra tanda firmada con depuración: desinstalás, perdés la base, y volvés a
> pagar los noventa segundos del GPS y a pegar la configuración de la nube.
> **Primero los secretos, después el merge.**

---

## Paso 1 · Generar la clave de firma, en Termux

**Por qué.** Cada corrida del workflow genera una clave de depuración NUEVA, y
Android no deja instalar un APK encima de otro firmado con una clave distinta:
dice «conflicto con un paquete». Con una clave propia, todas las tandas quedan
firmadas igual y se instalan una encima de la otra como cualquier actualización.

**Hasta el 2026-09-20 acá decía que hacía falta una computadora. Era falso** —
`keytool` viene con cualquier JDK, y en Android hay JDK.

### 1.1 · Instalar Termux

Desde F-Droid o desde su repositorio de GitHub. **No desde Play Store**: esa
versión está sin mantener hace años y falla al instalar paquetes.

### 1.2 · El JDK y la clave

```bash
pkg update
pkg install openjdk-17

keytool -genkeypair -v \
  -keystore sitd-hilux.jks -storetype JKS \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias sitd -dname "CN=SITD Hilux, O=SITD, C=UY"
```

Va a pedir una contraseña **dos veces** (la del keystore y la de la clave).
**Poné la misma las dos veces** y guardala en tu gestor de contraseñas: es la
que va en `FIRMA_STORE_PASS` y `FIRMA_KEY_PASS`.

### 1.3 · Pasarla a texto

```bash
base64 -w0 sitd-hilux.jks > sitd-hilux.jks.b64
cat sitd-hilux.jks.b64
```

Sale un chorro largo de letras y números, **todo en una sola línea**. Copiálo
entero — mantené apretado, «Seleccionar todo», copiar.

> **Guardá el `.jks` ANTES de seguir.** Compartilo a Drive, a tu gestor de
> contraseñas, a donde sobreviva a que se rompa el teléfono. **Si lo perdés no
> hay forma de volver a firmar una actualización**: habría que desinstalar y
> empezar de cero, para siempre. Eso es lo que hay que cuidar, más que las
> contraseñas.
>
> Y **no va al repositorio ni a un chat.** El repositorio es público.

### 1.4 · Cargar los cuatro secretos

En GitHub → repositorio `sitd-hilux` → **Settings** → **Secrets and variables**
→ **Actions** → **New repository secret**. Cuatro veces:

| Nombre | Valor |
|---|---|
| `FIRMA_JKS` | el chorro de `sitd-hilux.jks.b64`, todo en una línea |
| `FIRMA_STORE_PASS` | la contraseña que elegiste |
| `FIRMA_KEY_PASS` | la misma |
| `FIRMA_ALIAS` | `sitd` |

Los nombres van **exactos**: el workflow los busca así.

---

## Paso 2 · Mergear la rama

Recién ahora. Es lo que dispara una corrida nueva **y ya firmada con tu clave**.

En GitHub → **Pull requests** → abrir el de la rama
`claude/reglas-marcadores-2026-09-20` → **Merge**.

Trae, además del marcador unificado de las reglas:

- **`sitd-19`** — la contraseña de la nube deja de vivir en el teléfono: se usa
  una vez, se guarda el `refreshToken` y se borra. Un token se revoca desde la
  consola sin tocar la contraseña.
- **`sitd-20`** — la cascada del GPS vuelve a preguntar por qué modo empezar en
  **cada viaje**, en vez de una sola vez al abrir la aplicación.

### Cómo sabés que salió bien

Andá al release `ultimo` y mirá las notas. Si **desapareció** el cartel:

> ⚠ Firmado con la clave de DEPURACIÓN…

y dice que firmó con la clave propia, funcionó.

**Si el cartel sigue ahí**, algún secreto no quedó cargado: lo más común es que
`FIRMA_JKS` se haya pegado cortado o con un salto de línea. Volvé a copiarlo
entero.

---

## Paso 3 · La última desinstalación

Esta tanda **todavía pide desinstalar una vez**, y no es un error: lo que tenés
instalado hoy fue firmado con una clave de depuración distinta de la tuya.
Android no las deja convivir.

**Es la última.** De acá en adelante cada tanda se instala encima.

### Antes de desinstalar

1. **Subí lo que falte.** Aplicación → Sacar los datos → **Subir ahora**. Que
   diga `0 esperando`. Lo que ya está en la nube no se pierde.
2. Si querés el respaldo completo (el que lleva el recorrido), sacalo también.
   Va a Drive, **no a un chat**.

### Después de instalar

1. Aplicación → **Sacar los datos** → **Cambiar** → pegás la configuración de la
   nube. **Ésta es la última vez que la vas a pegar.**
2. El primer viaje después de instalar todavía va a tardar en enganchar el GPS:
   la aplicación no aprendió aún cuál modo entrega en este teléfono. **Del
   segundo viaje en adelante mide desde el primer segundo**, y ya no se olvida
   nunca más, porque la base sobrevive a las actualizaciones.

---

## Qué queda resuelto

| Antes | Después |
|---|---|
| Cada tanda: desinstalar | Se instala encima |
| Cada tanda: perder los viajes locales | La base sobrevive |
| Cada tanda: re-pegar la configuración de la nube | Se pega una vez |
| Cada viaje: 90 s hasta que el GPS engancha | Sólo el primero después de instalar |
| La contraseña de la nube, guardada en el teléfono | Un token revocable |

---

## Si algo sale mal

- **Termux dice que no encuentra `keytool`** → faltó `pkg install openjdk-17`,
  o hay que cerrar y volver a abrir Termux.
- **El release sigue diciendo «clave de DEPURACIÓN»** → revisá `FIRMA_JKS`: es
  el sospechoso número uno, por el largo.
- **Android sigue diciendo «conflicto con un paquete» en la SEGUNDA tanda
  firmada** → las dos no se firmaron con la misma clave. Pasa si se regeneró el
  keystore; tiene que ser el mismo archivo siempre.
- **Perdiste el `.jks`** → no hay vuelta: se genera uno nuevo, se cargan los
  secretos otra vez, y hay una desinstalación más. Por eso el paso 1.3 insiste.
