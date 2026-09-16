import java.io.FileInputStream
import java.util.Properties

// ── LA CLAVE DE FIRMA ───────────────────────────────────────────────────────
// No está en el repositorio y no puede estarlo: este repositorio es público.
// Llega por GitHub Secrets, y el workflow escribe con ellos un `key.properties`
// y un `firma.jks` que el `.gitignore` bloquea por partida doble.
//
// **Si el archivo no está, se firma con la clave de depuración**, que es lo que
// pasaba hasta ahora y lo que sigue pasando en una compilación local. La
// diferencia no es cosmética: la de depuración la genera Gradle nueva cada vez
// que no la encuentra, y un runner de GitHub arranca limpio, así que dos tandas
// salían con firmas distintas y Android no dejaba actualizar una sobre la otra
// — «conflicto con un paquete», y desinstalar borra la base.
val propiedadesDeFirma = Properties()
val archivoDeFirma = rootProject.file("key.properties")
val hayClavePropia = archivoDeFirma.exists()
if (hayClavePropia) {
    FileInputStream(archivoDeFirma).use { propiedadesDeFirma.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uy.gasta.sitd_hilux"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "uy.gasta.sitd_hilux"

        // Android 10. NO es el del telefono de desarrollo (Redmi 15, Android 15):
        // es el piso del telefono de destino, el Redmi Note 9, que es donde la
        // aplicacion va a vivir montada en la cabina. La restriccion la pone el
        // aparato viejo, no el nuevo.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayClavePropia) {
            create("propia") {
                storeFile = file(propiedadesDeFirma.getProperty("storeFile"))
                storePassword = propiedadesDeFirma.getProperty("storePassword")
                keyAlias = propiedadesDeFirma.getProperty("keyAlias")
                keyPassword = propiedadesDeFirma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // La propia si los secretos estan cargados; la de depuracion si no.
            // Nunca falla por falta de clave: un APK sin firmar no sirve para
            // nada, y una compilacion que no compila tampoco.
            signingConfig = if (hayClavePropia) {
                signingConfigs.getByName("propia")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
