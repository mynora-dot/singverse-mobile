plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val productVersion = System.getenv("SINGVERSE_VERSION") ?: "0.0.0"
val versionParts = Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)").matchEntire(productVersion)
    ?.groupValues?.drop(1)?.map { it.toLong() } ?: error("SINGVERSE_VERSION must be major.minor.patch")
check(versionParts[0] <= 2100 && versionParts[1] <= 999 && versionParts[2] <= 999) { "SINGVERSE_VERSION is outside Android versionCode range" }
val productCode = (versionParts[0] * 1000000 + versionParts[1] * 1000 + versionParts[2]).coerceAtLeast(1L)
check(productCode in 1..2100000000) { "SINGVERSE_VERSION is outside Android versionCode range" }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested) check(!System.getenv("SINGVERSE_VERSION").isNullOrBlank() && productVersion != "0.0.0") { "Release requires the version injected by Actions" }
val signingNames = listOf("SINGVERSE_MOBILE_KEYSTORE", "SINGVERSE_MOBILE_STORE_PASSWORD", "SINGVERSE_MOBILE_KEY_ALIAS", "SINGVERSE_MOBILE_KEY_PASSWORD")
val releaseSigning = signingNames.associateWith { System.getenv(it) }
if (releaseRequested) check(releaseSigning.values.all { !it.isNullOrBlank() }) { "Release requires all SINGVERSE_MOBILE signing variables" }

android {
    lint {
        checkReleaseBuilds = System.getenv("GITHUB_ACTIONS") != "true"
    }
    namespace = "com.mynora.singverse.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mynora.singverse.mobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = productCode.toInt()
        versionName = productVersion
    }

    if (releaseSigning.values.all { !it.isNullOrBlank() }) {
        signingConfigs.create("production") {
            storeFile = file(releaseSigning.getValue("SINGVERSE_MOBILE_KEYSTORE")!!)
            storePassword = releaseSigning.getValue("SINGVERSE_MOBILE_STORE_PASSWORD")
            keyAlias = releaseSigning.getValue("SINGVERSE_MOBILE_KEY_ALIAS")
            keyPassword = releaseSigning.getValue("SINGVERSE_MOBILE_KEY_PASSWORD")
        }
        buildTypes.getByName("release").signingConfig = signingConfigs.getByName("production")
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
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.5.1")
}
