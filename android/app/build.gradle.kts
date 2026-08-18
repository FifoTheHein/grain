import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live in android/key.properties, which is
// gitignored — see key.properties.example. A relative storeFile is resolved
// against the android/ directory; an absolute path is used as given.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

// Fail a release build rather than let it fall back to the debug keystore. A
// debug key is generated per machine, so an APK signed with one can only ever
// be updated from that same machine — Android rejects the install otherwise,
// and the uninstall it forces wipes every preference the app holds (Harvest
// credentials, ADO instances, mapping rules, templates).
//
// Scoped to release tasks so a debug run still works with no keystore present.
val wantsRelease = gradle.startParameter.taskNames.any { it.endsWith("Release") }
if (wantsRelease && !hasKeystore) {
    throw GradleException(
        "android/key.properties is missing, so the release build has nothing " +
            "to sign with. Copy android/key.properties.example and fill it " +
            "in — see 'Set up the Android release keystore' in the README."
    )
}

android {
    namespace = "com.fifothehein.grain"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.fifothehein.grain"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storePassword = keystoreProperties.getProperty("storePassword")
            storeFile = keystoreProperties.getProperty("storeFile")
                ?.let { rootProject.file(it) }
        }
    }

    buildTypes {
        release {
            // Null only on a debug-only machine, which the guard above has
            // already established is not building a release.
            signingConfig = if (hasKeystore) signingConfigs.getByName("release") else null
        }
    }
}

flutter {
    source = "../.."
}
