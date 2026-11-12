plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val productVersion = rootProject.file("../VERSION").readText().trim()
val versionParts = Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)").matchEntire(productVersion)
    ?.groupValues?.drop(1)?.map { it.toLong() } ?: error("VERSION must be major.minor.patch")
check(versionParts[1] <= 999 && versionParts[2] <= 999) { "VERSION minor/patch must be <= 999" }
val productCode = versionParts[0] * 1000000 + versionParts[1] * 1000 + versionParts[2]
check(productCode in 1..2100000000) { "VERSION is outside Android versionCode range" }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val signingNames = listOf("SINGVERSE_MOBILE_KEYSTORE", "SINGVERSE_MOBILE_STORE_PASSWORD", "SINGVERSE_MOBILE_KEY_ALIAS", "SINGVERSE_MOBILE_KEY_PASSWORD")
val releaseSigning = signingNames.associateWith { System.getenv(it) }
if (releaseRequested) check(releaseSigning.values.all { !it.isNullOrBlank() }) { "Release requires all SINGVERSE_MOBILE signing variables" }

android {
    namespace = "com.mynora.singverse.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mynora.singverse.mobile"
        if (providers.gradleProperty("singverseE2e").orNull == "true") applicationIdSuffix = ".e2e"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
    testImplementation("junit:junit:4.13.2")
    debugImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

tasks.withType<Test>().configureEach {
    systemProperty("singverse.computeContract", rootProject.projectDir.resolve("../contracts/openapi/compute-internal.openapi.json").canonicalPath)
}
