# Flutter / engine
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# Hive (adapters are registered manually but stay defensive)
-keep class hive.** { *; }

# Workmanager
-keep class be.tramckrijte.workmanager.** { *; }
-keep class androidx.work.** { *; }

# Strip Dart-side debug logging in release
-assumenosideeffects class kotlin.io.ConsoleKt { *; }
