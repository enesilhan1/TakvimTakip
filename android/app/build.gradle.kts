import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val imzaDosyasi = rootProject.file("key.properties")
val imza = Properties().apply {
    if (imzaDosyasi.exists()) imzaDosyasi.inputStream().use { load(it) }
}

android {
    namespace = "com.enesilhan.takvim_takip"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications zamanlama için java.time kullanıyor.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.enesilhan.takvim_takip"
        // Sürüm numaraları pubspec.yaml'daki "version: 1.0.0+1" satırından gelir.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Sürüm imzası: android/key.properties ve android/takvim_takip.jks
    // (ikisi de git'e girmez). Güncellemelerin telefondaki verileri silmeden
    // üstüne kurulabilmesi için her sürüm aynı anahtarla imzalanmalı.
    // Dosyalar yoksa (ör. başka bilgisayar) debug anahtarına düşer.
    signingConfigs {
        if (imzaDosyasi.exists()) {
            create("release") {
                keyAlias = imza.getProperty("keyAlias")
                keyPassword = imza.getProperty("keyPassword")
                storeFile = file(imza.getProperty("storeFile"))
                storePassword = imza.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (imzaDosyasi.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
