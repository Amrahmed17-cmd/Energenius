import java.util.Properties
import java.io.FileInputStream
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.energenius"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
    
    // Add lint configuration
    lint {
        baseline = file("lint-baseline.xml")
        abortOnError = false
    }
    
    // Add signing configurations for release builds
    signingConfigs {
        create("release") {
            // You will need to create a key.properties file with these values
            // in the android/ directory
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val properties = Properties()
                properties.load(FileInputStream(keystorePropertiesFile))
                
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
                storeFile = file(properties.getProperty("storeFile"))
                storePassword = properties.getProperty("storePassword")
            } else {
                // Fallback to debug signing if keystore not available
                // Try to find debug.keystore in different locations
                val appDebugKeystore = File(projectDir, "debug.keystore")
                val rootDebugKeystore = File(rootProject.projectDir, "debug.keystore")
                val homeDir = System.getProperty("user.home")
                val defaultDebugKeystore = File(homeDir, ".android/debug.keystore")
                
                when {
                    appDebugKeystore.exists() -> storeFile = appDebugKeystore
                    rootDebugKeystore.exists() -> storeFile = rootDebugKeystore
                    defaultDebugKeystore.exists() -> storeFile = defaultDebugKeystore
                    else -> {
                        // If no keystore found, set a placeholder that will be handled in buildTypes
                        storeFile = File(homeDir, ".android/debug.keystore") // This file may not exist
                        println("Warning: No debug keystore found. Release builds will be configured without signing.")
                    }
                }
                
                keyAlias = "androiddebugkey"
                keyPassword = "android"
                storePassword = "android"
            }
        }

        getByName("debug") {
            storeFile = file("${System.getProperty("user.home")}/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.energenius.app"  // Changed to a proper app ID
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Add security configurations
        manifestPlaceholders["appAuthRedirectScheme"] = "com.energenius.app"
    }

    buildTypes {
        release {
            // Use release signing config if available
            val releaseSigningConfig = signingConfigs.findByName("release")
            if (releaseSigningConfig?.storeFile?.exists() == true) {
                signingConfig = releaseSigningConfig
            } else {
                // If no signing config available, use debug configuration
                signingConfig = signingConfigs.getByName("debug")
            }
            
            // Apply the custom ProGuard rules
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            
            // Enable minification for better security
            isShrinkResources = true
            isMinifyEnabled = true
        }
        
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
