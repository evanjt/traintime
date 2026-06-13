import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// API key comes from local.properties (traintime.apiKey) or the
// TRAINTIME_API_KEY env var, matching Secrets.swift / Secrets.mc.
val traintimeApiKey: String = run {
    val localProperties = rootProject.file("local.properties")
    val fromFile = if (localProperties.exists()) {
        Properties()
            .apply { localProperties.inputStream().use { load(it) } }
            .getProperty("traintime.apiKey")
    } else {
        null
    }
    fromFile ?: System.getenv("TRAINTIME_API_KEY") ?: ""
}

android {
    namespace = "com.evanjt.traintime"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.evanjt.traintime"
        minSdk = 26
        targetSdk = 35
        versionCode = 3
        versionName = "0.3.0"

        buildConfigField("String", "TRAINTIME_API_KEY", "\"$traintimeApiKey\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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
}

dependencies {
    constraints {
        // Glance drags in fragment 1.1.0 transitively, which trips the
        // InvalidFragmentVersionForActivityResult lint check.
        implementation("androidx.fragment:fragment:1.8.5")
    }

    implementation(libs.androidx.core.ktx)
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

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)

    debugImplementation(libs.compose.ui.tooling)
}
