# HWCエラー対策: ハードウェア関連クラスの保護
-keep class android.hardware.** { *; }
-keep class android.view.** { *; }
-keep class android.graphics.** { *; }

# Flutter関連の保護
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 音声認識関連の保護
-keep class android.speech.** { *; }
-keep class android.media.** { *; }

# センサー関連の保護
-keep class android.hardware.Sensor** { *; }
-keep class android.hardware.SensorEvent** { *; }
-keep class android.hardware.SensorManager** { *; }

# Google Play Core API関連の保護（R8エラー対策）
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Flutter Play Store Split Application関連の保護
-keep class io.flutter.app.FlutterPlayStoreSplitApplication { *; }
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-dontwarn io.flutter.app.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.**