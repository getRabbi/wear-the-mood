import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (FCM push, §20) — wires android/app/google-services.json.
    id("com.google.gms.google-services")
}

// Release signing (CLAUDE.md §22). Local: android/key.properties (git-ignored).
// CI (Codemagic): the CM_* env vars injected by an android_signing reference.
// Falls back to debug signing so contributors without the keystore can build.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val hasReleaseSigning =
    keystorePropertiesFile.exists() || System.getenv("CM_KEYSTORE_PATH") != null

android {
    namespace = "com.fashionos.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fashionos.app"
        // Native Google Sign-In v7 uses Credential Manager (API 23+); ML Kit pose
        // detection needs API 21+; ML Kit **Subject Segmentation** (local-first
        // background removal, § local BG 2.1) requires API 24. Pin to 24 — the
        // highest floor wins. Keep in sync with `flutter_launcher_icons.
        // min_sdk_android` in pubspec.yaml and MIN_SDK in WtmBackgroundRemovalPlugin.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            } else if (System.getenv("CM_KEYSTORE_PATH") != null) {
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
                storeFile = file(System.getenv("CM_KEYSTORE_PATH"))
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Use the real release keystore when configured; else debug-sign so
            // `flutter build` still works for contributors (NOT Play-acceptable).
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
            // Flutter's Gradle plugin turns on R8 minification + resource
            // shrinking for release by default; with no keep rules that stripped
            // WorkManager (androidx.work) and crashed the app on launch
            // ("Failed to create an instance of androidx.work.impl.WorkDatabase").
            // Disable both for launch certainty — many reflective deps (WorkManager,
            // Supabase/GoTrue, RevenueCat, ML Kit) would otherwise need keep rules.
            // Revisit (re-enable + proper proguard rules) as a post-launch size win.
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

dependencies {
    // Official Google Play Install Referrer Client Library (§24) — deferred
    // deep-link install attribution. NOT the deprecated INSTALL_REFERRER
    // broadcast. Used by MainActivity's `wtm/install_referrer` MethodChannel.
    implementation("com.android.installreferrer:installreferrer:2.2")

    // Google ML Kit Subject Segmentation — the PRIMARY on-device background
    // removal engine on Android (local BG §2.1). Play-services-delivered: the
    // model is downloaded by Google Play services, so the user installs no extra
    // app and no weights ship in the APK. Requires minSdk 24 (set above).
    //
    // ⚠ Still 16.0.0-beta1 upstream — the only beta dependency in the build. The
    // whole path is behind the default-OFF LOCAL_BG_* Dart gates, and every
    // failure is typed, so a beta regression degrades to the existing Azure
    // BiRefNet cutout rather than breaking Add Garment. See LICENSES.md.
    implementation("com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1")

    // JVM unit tests for the pure engine logic (mask maths, metrics, cache
    // containment, preparation/error mapping) — no device, no emulator, no model
    // download. Run with `gradlew :app:testDebugUnitTest`.
    testImplementation("junit:junit:4.13.2")
}
