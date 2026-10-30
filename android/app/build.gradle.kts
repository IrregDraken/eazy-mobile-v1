import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseSigningConfigured = keystorePropertiesFile.exists() &&
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .all { !keystoreProperties.getProperty(it).isNullOrBlank() }
val allowDebugReleaseSigning = System.getenv("EAZY_ALLOW_DEBUG_RELEASE_SIGNING") == "true"

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
android {
    namespace = "com.eazy.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "com.eazy.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release {
            signingConfig = when {
                releaseSigningConfigured -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> signingConfigs.getByName("debug")
                else -> null
            }
        }
    }
}
val verifyEazyReleaseSigning = tasks.register("verifyEazyReleaseSigning") {
    doLast {
        if (!releaseSigningConfigured && !allowDebugReleaseSigning) {
            throw GradleException(
                "Release signing is not configured. Add android/key.properties and its private keystore. " +
                    "For CI/emulator-only release builds, explicitly set EAZY_ALLOW_DEBUG_RELEASE_SIGNING=true."
            )
        }
    }
}
tasks.configureEach {
    if ((name.startsWith("package") && name.contains("Release")) ||
        name == "assembleRelease" || name == "bundleRelease") {
        dependsOn(verifyEazyReleaseSigning)
    }
}
flutter { source = "../.." }
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
