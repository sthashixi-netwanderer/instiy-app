# ─────────────────────────────────────────────────────────────────────────────
# Instiy ProGuard / R8 rules (release builds)
# ─────────────────────────────────────────────────────────────────────────────

# Flutter engine & embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase (Cloud Messaging / Core)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Supabase / OkHttp / Retrofit style reflection
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# mobile_scanner (ML Kit barcode)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# local_auth (biometrics)
-keep class androidx.biometric.** { *; }

# Keep annotations & generic signatures used by JSON serialization / reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep enum values (often accessed reflectively by plugins)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Suppress warnings for desugared Java libs
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
