pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://developer.garmin.com/downloads/connect-iq/maven") }
    }
}

rootProject.name = "TrainTime"
include(":shared")
include(":phone")
include(":wear")
