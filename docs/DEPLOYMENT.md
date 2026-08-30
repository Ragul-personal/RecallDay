# Building and releasing RecallDay

Every push to `main` builds a signed APK in CI and publishes it as a numbered
GitHub Release. Nothing needs to be built by hand.

---

## How a release happens

`.github/workflows/build-apk.yml` runs on every push to `main`:

1. Decodes the release keystore from the `KEYSTORE_BASE64` secret into
   `android/app/release.p12`
2. `flutter pub get` → `flutter analyze` (non-blocking) → `flutter test`
3. `flutter build apk --release --split-per-abi`, stamping the release number
   into the APK's version
4. Publishes the three ABI-specific APKs to a release tagged `v<n>`

Install **`app-arm64-v8a-release.apk`** on any modern phone. The `armeabi-v7a`
build is for older 32-bit devices; `x86_64` is for emulators.

---

## Signing — why it matters more than it looks

Android only lets an APK install **over** an existing one when both are signed
by the same key. Without a keystore, Gradle falls back to a debug key that it
regenerates on every clean CI runner, so each release carried a different
signature, could not be installed over the last, and forced an uninstall — and
uninstalling wipes app-private storage.

Two repository secrets drive this:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | the release keystore, base64-encoded |
| `KEYSTORE_PASSWORD` | its password (also the key password) |

The keystore is a PKCS12 file with the alias `recallday`. It is **not** in the
repository and never should be.

> **If the keystore is lost, it cannot be recreated.** Future builds would get a
> different signature and could no longer be installed over the existing app,
> which means uninstalling and losing local data. Keep a copy somewhere safe.

If the secret is absent the build still succeeds, but is debug-signed and the
release notes say so explicitly.

---

## Building locally

Only needed for development — releases come from CI.

Requires the Flutter SDK (**3.32.0 or newer** — `workmanager` sets that floor),
the Android SDK with **platform 36** (the attachment plugins ship AARs compiled
against it), and JDK 17.

```bash
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```

The APK lands in `build/app/outputs/flutter-apk/`. A local build uses
`android/key.properties` if present, otherwise a debug key — so it will not
install over a CI release.

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`-r` reinstalls in place. It only works when the signatures match.

---

## Regenerating the icons

App and notification icons are generated from `Logo.png` at the repository root
and committed under `android/app/src/main/res/`. They only need regenerating if
the artwork changes.

- **Launcher** — `mipmap-*/ic_launcher.png` plus an adaptive
  `ic_launcher_foreground.png`. The mark sits at ~45% of the adaptive canvas:
  Android only guarantees the inner 72 of 108dp is visible, so anything larger
  gets clipped by a circular mask.
- **Notification** — `drawable-*/ic_stat_recallday.png`, a transparent
  monochrome silhouette. Android masks status-bar icons to their alpha channel,
  so an opaque image renders as a solid white block.

Both are named only from Dart strings, so `res/raw/keep.xml` stops the release
resource shrinker from stripping them. Removing that file causes a black screen
on launch in release builds.

---

## Version numbers

Releases are numbered 1, 2, 3… derived from the workflow run number minus
`VERSION_OFFSET` in the workflow file. The number is stamped into the APK via
`--build-name` / `--build-number`, so the version Android reports matches the
release it came from.
