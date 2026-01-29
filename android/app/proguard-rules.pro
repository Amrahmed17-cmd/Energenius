# Flutter Proguard Rules

# Keep `Companion` object fields of serializable classes.
# This avoids serializer lookup through `getDeclaredClasses` as done for named companion objects.
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    static ** Companion;
}

# Keep `serializer()` on companion objects (both default and named) of serializable classes.
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1>$Companion {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep Flutter wrapper classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep Dart VM services
-keep class com.google.gson.** { *; }

# Prevent R8 from stripping interface information from TypeAdapter classes.
# These are used for JSON serialization in Firestore.
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# FirebaseUI for Auth
-keep class com.firebase.ui.auth.** { *; }

# Keep custom model classes (used with Firestore)
-keep class com.example.energenius.models.** { *; }

# Firebase database classes
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Prevent R8 from leaving Data objects empty
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Generated files by Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }

# Enums are commonly used with Gson
-keepclassmembers enum * { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Fixes for R8 optimization failures
-dontobfuscate
-dontoptimize 
-dontpreverify
-ignorewarnings

# Special rule for Flutter's SDK
-keep class androidx.lifecycle.** { *; }

# Flutter specific ProGuard rules

# Keep Dart VM
-keep class io.flutter.plugin.editing.** { *; }

# Firebase rules
-keep class com.google.firebase.** { *; }
-keepnames class com.google.firebase.** { *; }
-keepnames class com.firebase.** { *; }

# Secure communication rules
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Gson specific classes
-keep class sun.misc.Unsafe { *; }
-dontwarn sun.misc.Unsafe
-keep class com.google.gson.** { *; }

# Security-specific rules
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,Exceptions,InnerClasses
-renamesourcefileattribute SourceFile
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5

# Keep specific security-critical components
-keep class javax.** { *; }
-keep class java.** { *; }
-keep class android.util.** { *; }
-keep class androidx.security.** { *; }

# Secure R8 optimization
-repackageclasses
-allowaccessmodification 