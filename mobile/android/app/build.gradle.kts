import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé de publication : android/key.properties (jamais versionné), écrit à la main en local
// ou par le workflow GitHub à partir des secrets du dépôt.
val fichierCle = rootProject.file("key.properties")
val cle = Properties().apply { if (fichierCle.exists()) FileInputStream(fichierCle).use { load(it) } }

android {
    namespace = "cm.cetic.mezesse.cetic_mezesse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cm.cetic.mezesse.cetic_mezesse"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (fichierCle.exists()) {
                storeFile = file(cle.getProperty("storeFile"))
                storePassword = cle.getProperty("storePassword")
                keyAlias = cle.getProperty("keyAlias")
                keyPassword = cle.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sans key.properties, on retombe sur la clé de débogage pour pouvoir tester en local ;
            // le workflow GitHub, lui, refuse de publier un APK signé ainsi.
            signingConfig = signingConfigs.getByName(if (fichierCle.exists()) "release" else "debug")
            // Règles R8 propres à l'application (WorkManager : voir le fichier).
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    // Vérification et téléchargement des mises à jour en arrière-plan, application fermée
    // (VerificationMiseAJour.kt).
    implementation("androidx.work:work-runtime-ktx:2.10.0")
}
