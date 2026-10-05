plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.viyo.app"
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
        applicationId = "com.viyo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Real release signing, sourced entirely from env vars (never a
    // committed file) — same "secrets live in GitHub Actions, not the
    // repo" convention main.yml's own --dart-define secrets already
    // follow. Falls back to the debug key when those aren't set (a
    // local `flutter run --release`, or a CI run before the 4 secrets
    // below are configured) so this never hard-fails the build; it
    // just produces a debug-signed APK like before in that case.
    val hasReleaseSigning = !System.getenv("ANDROID_KEYSTORE_BASE64").isNullOrBlank()
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                val keystoreBytes = java.util.Base64.getDecoder()
                    .decode(System.getenv("ANDROID_KEYSTORE_BASE64"))
                val decodedKeystoreFile = File(project.buildDir, "release-signing.keystore")
                decodedKeystoreFile.parentFile.mkdirs()
                decodedKeystoreFile.writeBytes(keystoreBytes)

                storeFile = decodedKeystoreFile
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseSigning) "release" else "debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// Push notifications (firebase_messaging) need this applied, but the
// plugin fails the build outright if google-services.json isn't
// present yet — so only apply it once that file actually exists.
// Drop your Firebase project's google-services.json into this
// directory (android/app/) to activate push notifications; nothing
// else needs to change.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
