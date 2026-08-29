# RecallDay — personal spaced-repetition reminders

A minimalist, dark-first study companion that pings you to revise at scientifically-tuned intervals until you actually remember the material. **Local-only build**: no accounts, no cloud, no analytics, no ads.

## Build it for your phone

One command on a computer with Flutter SDK installed:

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

Then install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` on your Android phone via `adb install` or by copying the file across. Full instructions in [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).

The same APK works on any Android 7.0+ device.

## What it does

You add a topic. You pick how hard it is. RecallDay keeps reminding you to revise it on a spaced schedule until you mark it remembered. Each review you grade Forgot / Hard / Good / Easy, and the next interval adapts.

- Persistent reminders (re-fire daily until reviewed), naming the subject and topic
- Adaptive scheduling (SM-2 hybrid, see below)
- Calendar view, 30-day analytics, subject-by-subject retention ranking
- Markdown notes per topic
- Swipe a topic to delete it; long-press a subject to edit or delete it
- Automatic backups that survive uninstall (see below)
- Dark-first Material 3 UI

## Architecture

```
lib/
├── main.dart                       — bootstrap (Hive, notifications, WorkManager)
├── core/
│   ├── theme/app_theme.dart        — Material 3 dark + light palettes
│   ├── router/app_router.dart      — go_router 14
│   ├── constants/                  — palette + icon catalog
│   └── utils/                      — date label helpers
├── domain/
│   ├── entities/                   — pure Dart Subject, Topic, Review
│   ├── repositories/               — abstract interfaces
│   └── usecases/
│       └── spaced_repetition_engine.dart   ← the brain
├── data/
│   ├── models/                     — Hive @HiveType adapters (typeIds 1, 2, 3)
│   └── repositories/               — Hive-backed implementations
├── services/
│   ├── storage_service.dart        — Hive bootstrap + compaction
│   ├── backup_service.dart         — JSON snapshot to shared storage + restore
│   ├── notification_service.dart   — flutter_local_notifications + tz
│   └── scheduler_worker.dart       — WorkManager periodic re-arm
└── presentation/
    ├── providers/providers.dart    — Riverpod streams + commands
    ├── pages/                      — Today, Subjects, Calendar, Analytics, Settings, ...
    └── widgets/                    — TopicCard, EmptyState, SwipeToDelete, ...
```

Clean-architecture-lite: presentation depends on domain, never on data. Data depends on domain. Services live alongside data.

## Spaced repetition

`SpacedRepetitionEngine` (in `lib/domain/usecases/`) is a pure function with two phases:

1. **Bootstrap** (`repetitions < 2`): walks a fixed Leitner ladder `[1, 3, 7, 15, 30, 60, 90]` days.
2. **Steady state** (`repetitions ≥ 2`): SM-2-style multiplicative `next = currentInterval × ease × ratingMultiplier`.

Ease updates per rating (Forgot −0.20, Hard −0.15, Good 0.00, Easy +0.15), clamped to `[1.30, 3.00]`. A `Forgot` rating at any stage rewinds to the first ladder rung. Hybrid was chosen because pure SM-2 has no useful first-interval prior, while pure Leitner can't adapt to topics the user knows well.

Engine invariants are pinned by tests:

```bash
flutter test
```

## Backup & restore

Android deletes an app's private data directory on uninstall — where Hive keeps its boxes — and no flag changes that. So the data is mirrored somewhere the package manager doesn't own. Two independent mechanisms:

1. **Android Auto Backup.** `allowBackup="true"` plus the rules in `res/xml/backup_rules.xml` and `res/xml/data_extraction_rules.xml`. Google backs the Hive files up to the user's account and restores them automatically on reinstall. Free and invisible, but only when device backup is on and the app is installed via Play or `adb restore`.

   Both rule files are **exclude-only on purpose**. Adding a single `<include>` flips Auto Backup from "everything" to an allow-list, and Hive does *not* live in the `file` domain — `getApplicationDocumentsDirectory()` resolves to `/data/data/<pkg>/app_flutter`, which is `domain="root" path="app_flutter"`.

2. **A JSON snapshot in shared storage** (`Documents/RecallDay/recallday-backup.json`), written by `BackupService` after every change and left untouched by uninstall. Restore happens automatically on first launch into an empty database, or on demand from Settings.

   Writing there by raw path needs "All files access" on Android 11+, so `BackupService` *probes* for a writable directory rather than guessing from API level, and Settings reports honestly whether the location it landed on actually survives uninstall. `MANAGE_EXTERNAL_STORAGE` is fine for a sideloaded personal build; it would need justification for Play.

Settings also offers "Copy JSON to clipboard" as a third, manual copy.

## Storage footprint

Hive uses a binary append-only log. Approximate disk costs:

- One Subject ≈ 120 bytes
- One Topic ≈ 280 bytes (varies with notes length)
- One Review ≈ 70 bytes

A heavy user with 1000 topics and 10000 reviews fits in ~1 MB on disk. Use **Settings → Compact storage** after bulk deletions to reclaim tombstoned space.

## Notification reliability

The hardest problem in this app, by a long way. See [`docs/NOTIFICATION_RELIABILITY.md`](docs/NOTIFICATION_RELIABILITY.md) for the layered strategy and what we *can* and *cannot* guarantee on stock Android vs. OEM-modified builds. Short version: stock Android is fine; if you're on Xiaomi/OnePlus/Samsung, exempt RecallDay from battery optimization.

## What's intentionally not here

- **No accounts, no Firebase, no cloud sync.** Backups are plain JSON files on your own phone; nothing is uploaded. The app requests no network permissions.
- **No analytics.** No telemetry leaves your device.
- **No streaks-as-pressure.** The streak counter is informational; missing a day doesn't reset progress.
- **No widgets.** Homescreen widgets need per-platform native modules — significant work, deferred.
