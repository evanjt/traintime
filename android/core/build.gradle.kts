import java.util.Properties

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

// API key comes from local.properties (traintime.apiKey) or the
// TRAINTIME_API_KEY env var, matching Secrets.swift / Secrets.mc. Lives here
// now so both :app and :wear read it through com.evanjt.traintime.core.BuildConfig.
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
    namespace = "com.evanjt.traintime.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        buildConfigField("String", "TRAINTIME_API_KEY", "\"$traintimeApiKey\"")
    }

    buildFeatures {
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
    // Exposed as api() so :app and :wear pick these up transitively — the shared
    // models, API client, prefs and location service return these types.
    api(libs.androidx.core.ktx)
    api(libs.datastore.preferences)
    api(libs.datastore)
    api(libs.okhttp)
    api(libs.kotlinx.serialization.json)
    api(libs.kotlinx.coroutines.android)
    api(libs.kotlinx.coroutines.play.services)
    api(libs.play.services.location)
    api(libs.play.services.wearable)
}
