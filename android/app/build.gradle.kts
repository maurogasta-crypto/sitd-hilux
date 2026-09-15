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

    buildTypes {
        release {
            // Se firma con la clave de depuracion a proposito. La aplicacion no
            // va a Play Store: se instala por costado desde el APK que compila
            // GitHub Actions. Si algun dia va a Play Store, aca entra una clave
            // de verdad, y su contrasena NO entra a este repositorio.
            signingConfig = signingConfigs.getByName("debug")
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
