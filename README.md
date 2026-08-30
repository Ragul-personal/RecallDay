# RecallDay — personal spaced-repetition reminders

A minimal study companion that reminds you to revise at widening intervals until
the material sticks. **Local-only**: no accounts, no cloud, no analytics, no ads.

## Get the app

**[ragul-personal.github.io/RecallDay](https://ragul-personal.github.io/RecallDay/)**
— a plain download page with install steps and a QR code. That's the link to
send people; this repository is not the front door.

Every push to `main` builds a signed APK and attaches it to the
[latest release](https://github.com/Ragul-personal/RecallDay/releases/latest),
which the download page links straight to. `app-arm64-v8a-release.apk` is the
build for modern phones.

Releases are signed with a stable key, so a new version installs **over** the
previous one and keeps your data. See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)
for how that pipeline works and how to build locally.

## What it does

You add a Subject, then Topics inside it. RecallDay schedules each topic's
revisions and reminds you when they're due.

- **Today** shows only what is due now — mark each **Done** or **Not done**
- **Reminders** name the subject and topic, and re-fire daily until actioned
- **Two daily summaries** at 6am and 8pm, sent only when something is pending
- **Attachments** per topic: images, video, documents, web and YouTube links
- **Calendar** plots completed revisions backwards and scheduled ones forwards
- **Progress** tracks streaks, activity and per-subject mastery
- **Light and dark themes**, switchable

## Architecture

Clean-architecture-lite. `presentation` depends on `domain`, never on `data`.
`data` implements `domain`'s interfaces. `services` own everything that talks to
the platform.

```
lib/
├── main.dart                    — guarded bootstrap; always reaches runApp()
├── core/
│   ├── constants/               — subject colour + icon catalogue
│   ├── router/app_router.dart   — go_router; tabs in a StatefulShellRoute
│   ├── theme/
│   │   ├── app_theme.dart       — brand palette, light + dark, every component
│   │   └── app_tokens.dart      — spacing, radii, motion — the 4pt grid
│   └── utils/date_utils.dart    — relative date labels
├── domain/                      — pure Dart, no Flutter, no I/O
│   ├── entities/                — Subject, Topic, Review, Attachment
│   ├── repositories/            — abstract interfaces
│   └── usecases/
│       └── spaced_repetition_engine.dart   ← the scheduling brain
├── data/
│   ├── models/                  — Hive @HiveType adapters (typeIds 1, 2, 3)
│   └── repositories/            — Hive-backed implementations
├── services/                    — the platform edge
│   ├── storage_service.dart     — Hive bootstrap + box accessors
│   ├── backup_service.dart      — snapshots, folder sync, import/export
│   ├── saf_service.dart         — Storage Access Framework bridge
│   ├── attachment_service.dart  — picking and importing files
│   ├── notification_service.dart— reminders + the two daily digests
│   └── scheduler_worker.dart    — WorkManager periodic alarm re-arm
└── presentation/
    ├── providers/
    │   ├── providers.dart       — READ side: derived state (re-exports below)
    │   ├── topic_commands.dart  — WRITE side: every mutation
    │   └── theme_provider.dart  — light/dark/system, persisted
    ├── pages/                   — one file per screen
    └── widgets/                 — AppCard, TopicCard, EmptyState, …
```

Two boundaries worth knowing:

- **Reads and writes are separate.** `providers.dart` holds derived state only;
  anything that changes data lives in `topic_commands.dart`. It re-exports the
  commands, so a screen still needs one import.
- **Hive is app-private; the user's folder is the durable copy.** Hive needs a
  real filesystem path and cannot live on a SAF tree, so the database is
  internal and mirrored to the chosen folder after every change.

## Spaced repetition

`SpacedRepetitionEngine` (`lib/domain/usecases/`) is a pure function — no I/O,
fully unit-tested — with two phases:

1. **Bootstrap** (`repetitions < 2`): walks a fixed ladder `[1, 3, 7, 15, 30,
   60, 90]` days.
2. **Steady state** (`repetitions ≥ 2`): SM-2-style
   `next = currentInterval × ease × ratingMultiplier`.

The day a topic is created is its first exposure, not a revision — the first
revision lands one ladder step later.

> **Note on ease.** The engine models four ratings with per-rating ease deltas,
> but the UI now records a single neutral "Done", so in practice ease stays at
> its default and intervals follow the ladder. The grading model is kept
> deliberately: it is pure, tested, and the natural place to reintroduce
> difficulty-aware scheduling.

```bash
flutter test    # engine invariants
```

## Storage and backup

Android deletes an app's private directory on uninstall, so the durable copy has
to live outside it. The user nominates a folder once, via the Storage Access
Framework, and RecallDay keeps it current:

```
<chosen folder>/
├── recallday-backup.json     — the database; rewritten on every change
└── RecallDay-files/
    └── <topicId>/<file>      — one copy per attachment, written once
```

Attachments are **not** bundled into an archive for the automatic backup.
Re-zipping every file on each edit meant a topic rename rebuilt tens of
megabytes in memory and pushed it through a method channel — enough to exhaust
the heap and get the process killed. They are immutable once added, so each is
streamed across exactly once.

`Export` bundles the database and every attachment into one file for sharing;
`Import` accepts that file, or a folder holding an unpacked backup. Picking a
folder is what makes attachments recoverable: a file grant covers that file
alone, so a lone data file can only carry records.

Raw `/storage/emulated/0` paths were abandoned — writes there could succeed
while the matching read failed with `EACCES`, `File.exists()` returned false on
a denied read, and the OS silently rewrote file extensions. The rationale is
documented at the top of `backup_service.dart`.

## Notification reliability

The hardest problem in this app. See
[`docs/NOTIFICATION_RELIABILITY.md`](docs/NOTIFICATION_RELIABILITY.md) for the
layered strategy and what can and cannot be guaranteed. Short version: stock
Android is fine; on Xiaomi, OnePlus or Samsung, exempt RecallDay from battery
optimisation.

## What's intentionally not here

- **No accounts, no cloud sync, no analytics.** Backups are plain files on your
  own phone. The single network permission is for `google_fonts` fetching the
  Inter typeface on first launch — no app data leaves the device.
- **No streaks-as-pressure.** The streak is informational; a missed day moves
  the revision without penalising progress.
- **No home-screen widgets.** These need per-platform native modules —
  significant work, deferred.
