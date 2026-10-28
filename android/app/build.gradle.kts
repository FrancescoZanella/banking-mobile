import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chiave di firma fuori dalla repo (%LOCALAPPDATA%\BankingMobile\signing), come i
// dati della versione web. BANKING_MOBILE_KEY_PROPERTIES può indicarne un'altra.
val keyPropertiesFile = File(
    System.getenv("BANKING_MOBILE_KEY_PROPERTIES")
        ?: "${System.getenv("LOCALAPPDATA")}/BankingMobile/signing/key.properties"
)
val keyProperties = Properties().apply {
    if (keyPropertiesFile.isFile) keyPropertiesFile.inputStream().use { load(it) }
}

android {
    namespace = "com.francescozanella.bankingmobile"
    // Richiesti dai plugin (flutter_secure_storage, sqflite_sqlcipher, local_auth, …).
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Richiesto da flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.francescozanella.bankingmobile"
        // Android 9+: BiometricPrompt e Keystore moderno.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyProperties.isEmpty) return@create
            storeFile = file(keyProperties.getProperty("storeFile"))
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8: codice ridotto e offuscato, risorse inutili rimosse.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

// Mai una release firmata con la chiave di debug: senza chiave la build si ferma.
tasks.matching { it.name.startsWith("assemble") || it.name.startsWith("bundle") }.configureEach {
    if (name.contains("Release")) {
        doFirst {
            if (keyProperties.isEmpty) throw GradleException("Chiave di firma non trovata: ${keyPropertiesFile.path}")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Custom Tabs effimere (incognito) per il login con la banca.
    implementation("androidx.browser:browser:1.9.0")
}
