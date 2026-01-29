pluginManagement {
    // Load the Flutter SDK path from local.properties
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    // Include the Flutter tools Gradle build
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google() // Google's Maven repository
        mavenCentral() // Central Maven repository
        gradlePluginPortal() // Gradle Plugin Portal for additional plugins
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0" // Flutter plugin loader
    id("com.android.application") version "8.7.0" apply false // Android Gradle Plugin
    id("com.google.gms.google-services") version "4.4.2" apply false // Firebase services
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false // Kotlin Android plugin
}

include(":app") // Include the app module