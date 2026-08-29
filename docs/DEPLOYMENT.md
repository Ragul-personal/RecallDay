# Build a personal APK and install it on your phone

This is the simplest path: build the APK on a computer, transfer it to any Android phone, install. No Google Play, no developer account, no signing key required.

The same APK installs on any Android device running 7.0 or newer.

---

## What you need on the computer

- Flutter SDK 3.27 or newer (`flutter --version`)
- Android SDK Platform 34 (Android Studio installs this)
- Java 17 (`java -version`)
- A USB cable, OR a way to copy a file to the phone (Drive / email / file manager)

If you don't have Flutter, install it: https://docs.flutter.dev/get-started/install

---

## Build the APK

From the project root:

```bash
# 1. Pull dependencies (first time only)
flutter pub get

# 2. Build a release APK split per CPU architecture.
#    --split-per-abi produces three smaller APKs instead of one fat one.
flutter build apk --release --split-per-abi
```

This produces three files under `build/app/outputs/flutter-apk/`:

| File | Use this if your phone is… | Approx. size |
|---|---|---|
| `app-arm64-v8a-release.apk` | Any phone made after ~2017 (99% of users) | ~14 MB |
| `app-armeabi-v7a-release.apk` | Older 32-bit Android device | ~13 MB |
| `app-x86_64-release.apk` | Android emulator / x86 tablet | ~14 MB |

> Don't know which? Pick `arm64-v8a`. If your phone refuses to install it, try `armeabi-v7a`.

If you'd prefer a single fat APK (works on every architecture, ~30 MB):

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

---

## Install on your phone

### Option A — USB (fastest if you have a cable)

```bash
# Plug in the phone, enable USB debugging in Developer Options
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Option B — Transfer the file

1. Copy the APK to your phone via Google Drive, email attachment, USB drag-and-drop, or any file-sharing app.
2. On the phone, open the file via the system file manager. Android will ask "Allow installs from this source?" — say yes for your file manager.
3. Tap Install. You'll see "App not installed by Play Protect" on first run; tap "Install anyway." This is normal for sideloaded APKs.

### Option C — Build and run directly on the phone

If your phone is plugged in:

```bash
flutter run --release
```

This compiles, installs, and launches in one step.

---

## After installing

On first launch RecallDay asks for two permissions:

1. **Notifications** (Android 13+): without this, no reminders.
2. **Schedule exact alarms** (Android 12+): without this, reminders are batched and may drift by up to 15 minutes.

Grant both. If you skip them you can re-request from **Settings → Re-request permissions**.

For the most reliable reminders on Xiaomi / OnePlus / Samsung / Vivo devices, also do:

> **Android Settings → Apps → RecallDay → Battery → Don't optimize**

Without this exemption, OEM battery managers occasionally kill scheduled alarms.

---

## Updating

When you change the code and want a new APK:

```bash
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The `-r` flag reinstalls without losing your data. Hive boxes are preserved across reinstalls because the package name (`com.recallday.app`) stays the same.

---

## Reducing APK size further

If 14 MB still feels large:

- Build with `--obfuscate --split-debug-info=build/symbols` (saves ~1.5 MB and obfuscates the Dart code).
- Drop unused dependencies in `pubspec.yaml` (we already trimmed `firebase_*`, `google_sign_in`, `flutter_svg`, `flutter_slidable`).
- Set `versionCode` properly so `adb install -r` always works.

```bash
flutter build apk --release --split-per-abi \
  --obfuscate --split-debug-info=build/symbols
```

---

## Common errors

- **`Could not resolve all artifacts ... google-services`**: you have an old `build.gradle` that still references Firebase. Confirm the file matches the version in this repo.
- **`Execution failed for task ':app:processReleaseResources'`** with a missing icon: run `dart run flutter_launcher_icons` after placing your icon at `assets/icons/app_icon.png`.
- **`SDK location not found`**: create `android/local.properties` with `sdk.dir=/path/to/Android/sdk` and `flutter.sdk=/path/to/flutter`.
