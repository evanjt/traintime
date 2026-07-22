import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.roborazzi)
}

// The TRAINTIME_API_KEY buildConfigField now lives in :core (read by TrainApi via
// com.evanjt.traintime.core.BuildConfig), shared with :wear.

// Release signing. Local builds read android/keystore.properties; CI passes the
// same values via env. Without either, release falls back to debug signing so
// bundleRelease still runs for local R8 testing (Play rejects debug-signed
// uploads, so a real upload keystore is required to actually ship).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    keystoreProperties.getProperty(prop) ?: System.getenv(env)
val releaseStoreFile: String? = signingValue("storeFile", "KEYSTORE_FILE")

android {
    namespace = "com.evanjt.traintime"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.evanjt.traintime"
        minSdk = 26
        // Play requires API 36 for phone apps from 31 Aug 2026.
        targetSdk = 36
        versionCode = 15
        versionName = "0.6.1"
    }

    signingConfigs {
        create("release") {
            if (releaseStoreFile != null) {
                storeFile = rootProject.file(releaseStoreFile)
                storePassword = signingValue("storePassword", "KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (releaseStoreFile != null) "release" else "debug",
            )
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Ship native symbols so Play can symbolicate native crashes and ANRs.
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all { it.systemProperty("robolectric.graphicsMode", "NATIVE") }
        }
    }
}

dependencies {
    constraints {
        // Glance drags in fragment 1.1.0 transitively, which trips the
        // InvalidFragmentVersionForActivityResult lint check.
        implementation("androidx.fragment:fragment:1.8.5")
    }

    implementation(project(":core"))

    implementation(libs.androidx.core.ktx)
    // Per-app language backport: AppCompatDelegate.setApplicationLocales.
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)
    implementation(libs.work.runtime.ktx)
    implementation(libs.datastore.preferences)
    implementation(libs.datastore)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.play.services.location)

    // Garmin Connect IQ Mobile SDK: cross-ecosystem bridge to a Garmin watch,
    // relayed by the Garmin Connect Mobile app. Public on Maven Central.
    implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.2.0@aar")

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)

    // Roborazzi Compose screenshot tests (JVM via Robolectric, no emulator).
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
    testImplementation(libs.compose.ui.test.junit4)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
}
