import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Release signing. Must use the same key as :app: Play delivers both under one
// listing and the Data Layer only pairs same-signed builds. Reads the shared
// android/keystore.properties (CI passes env). Without either, release falls
// back to debug signing so bundleRelease still runs locally.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    keystoreProperties.getProperty(prop) ?: System.getenv(env)
val releaseStoreFile: String? = signingValue("storeFile", "KEYSTORE_FILE")

android {
    namespace = "com.evanjt.traintime.wear"
    compileSdk = 35

    defaultConfig {
        // Same applicationId as :app, required for the Wearable Data Layer to
        // pair the watch and phone. Shipped as a separate APK under one Play
        // listing. Distinct versionCode space (1000+) from the phone's.
        applicationId = "com.evanjt.traintime"
        minSdk = 30
        targetSdk = 35
        versionCode = 1011
        versionName = "0.5.3"
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
        }
    }
}

dependencies {
    constraints {
        // Wear/activity-compose drags in an old fragment transitively, which trips
        // the InvalidFragmentVersionForActivityResult lint check (same as :app).
        implementation("androidx.fragment:fragment:1.8.5")
    }

    implementation(project(":core"))

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(libs.wear.compose.material)
    implementation(libs.wear.compose.foundation)
    implementation(libs.wear.compose.navigation)
    implementation(libs.wear.ongoing)
    implementation(libs.play.services.wearable)

    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
}
