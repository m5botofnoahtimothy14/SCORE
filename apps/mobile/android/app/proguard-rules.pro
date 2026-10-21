# ============================================================
# TeachCross — ProGuard / R8 rules
#
# Applied to the release build (isMinifyEnabled = true,
# isShrinkResources = true). Every rule here protects a class
# that is looked up reflectively at runtime, or that would
# otherwise be stripped and crash the app on first launch.
# ============================================================

# ── Flutter engine / embedding ──────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# ── Flutter plugins (entry points invoked by the engine) ─────────
-keep class dev.flutter.plugins.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── AndroidX / Play Services / Firebase ─────────────────────────
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class androidx.** { *; }
-dontwarn androidx.**

# ── Kotlin ──────────────────────────────────────────────────────
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-dontwarn kotlin.**

# ── local_notifications: the scheduled-notification receiver and
#    its intent extras are resolved by name at alarm time. ──────
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
-keep class * extends com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
-keep class * extends com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver
-dontwarn com.dexterous.**

# ── image_picker / file access ──────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }

# ── Supabase / OkHttp / Kotlinx ─────────────────────────────────
-keep class io.supabase.** { *; }
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**

# ── Keep annotations and generic signatures so R8 can resolve
#    them without stripping the annotation metadata. ─────────────
-keepattributes *Annotation*, InnerClasses, Signature, Exceptions

# ── Suppress warnings for optional/large desugared APIs ────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn java.lang.invoke.**
