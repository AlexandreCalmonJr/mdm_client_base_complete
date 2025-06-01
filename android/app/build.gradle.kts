plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mdm_client_base"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Habilitar suporte para Java 11+ (necessário para flutter_local_notifications)
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Habilitar core library desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Application ID baseado no seu projeto existente
        applicationId = "com.example.mdm_client_base"
        // Usando as configurações do Flutter
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Suporte para múltiplas arquiteturas
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            isDebuggable = true
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring (necessário para flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // Suporte para múltiplas versões do Dex
    implementation("androidx.multidex:multidex:2.0.1")
}