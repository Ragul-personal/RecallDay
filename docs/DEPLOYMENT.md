# Building and releasing RecallDay

Every push to `main` builds a signed APK in CI and publishes it as a GitHub
Release, which the download page at
[ragul-personal.github.io/RecallDay](https://ragul-personal.github.io/RecallDay/)
links to. Nothing needs to be built by hand.

---

## How a release happens

`.github/workflows/build-apk.yml` runs on every push to `main`:

1. Decodes the release keystore from the `KEYSTORE_BASE64` secret into
   `android/app/release.p12`
2. `flutter pub get` → `flutter analyze` (non-blocking) → `flutter test`
3. `flutter build apk --release --split-per-abi`, stamping the version from
   `pubspec.yaml` into the APK
4. Publishes the three ABI-specific APKs to a release tagged `v<version>`

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

Two numbers, and they are not the same thing.

**versionName** — `1.0.0`, the only one anyone sees. It comes from `version:`
in `pubspec.yaml`. Edit that line to ship a new version; CI reads it, stamps it
into the APK with `--build-name` and tags the release `v1.0.0`. Pushing without
changing it refreshes the existing release in place instead of creating another
one.

**versionCode** — an integer Android requires to *never decrease*. An APK whose
code is lower than the installed one is rejected as a downgrade, and the only
way past that is uninstalling, which wipes app-private storage. Releases were
previously numbered off the workflow run number and reached 24 on real phones,
so the code stays tied to `github.run_number` — monotonic by definition — while
the name restarts at `1.0.0`. Nobody sees it; it exists so upgrades keep
working.

---

## The download page

`docs/index.html` is a static page served by GitHub Pages at
<https://ragul-personal.github.io/RecallDay/>. It links to
`/releases/latest/download/app-arm64-v8a-release.apk`, a URL GitHub keeps
pointed at the newest release — so the page never needs republishing when a
version ships. The version, size and date shown on it are fetched from the
public GitHub API at page load, falling back to a static caption if that call
fails.

Pages is served from the `main` branch's `/docs` folder (Settings → Pages →
Source: *Deploy from a branch*). `docs/.nojekyll` stops Jekyll from processing
the folder, so the HTML is served exactly as committed.
