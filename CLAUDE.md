# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## The single most important operational fact

**There is no Flutter SDK on this machine.** `flutter`, `dart` and `adb` are not
installed and the user has declined to install them. You cannot compile, run,
or test locally.

**CI is the only compiler.** Every push to `main` runs
`.github/workflows/build-apk.yml`, which is the only way to find out whether the
code builds. Plan accordingly: batch related changes, verify statically before
pushing, and expect a ~6 minute round trip per attempt.

Static checks worth running before any push (all are read-only shell/python):

- Delimiter balance across every `.dart` and `.kt` file
- Relative imports resolve to a symbol actually used in the file
- **Method-inventory diff against `git show HEAD:<file>`** — see the warning below

### Warning: scripted edits have silently deleted code here

Removing a method by slicing from its doc comment to the *next* doc comment has
twice deleted the functions in between — once in `saf_service.dart` (5 methods),
once in `MainActivity.kt` (8 functions). Brace counting cannot detect this,
because whole functions disappear and the file stays balanced. Both times CI
caught it, not the local checks.

Prefer rewriting a whole file (heredoc / Write) or an exact-match string
replacement that asserts it matched exactly once. Line-oriented `sed`/`perl -p`
across a multi-line construct is what caused both incidents.

When deleting a method with a script, walk its braces to find the end, then diff
the method inventory against the previous revision:

```bash
git show HEAD:path/to/file.dart | grep -oE "Future<[^(]*> \w+\(" | sort
grep -oE "Future<[^(]*> \w+\(" path/to/file.dart | sort
```

## Commands

```bash
flutter pub get
flutter analyze                 # ~34 style infos are pre-existing; errors are not
flutter test                    # 14 engine tests
flutter test --plain-name "first \"good\" review"   # single test by name
flutter build apk --release --split-per-abi
```

Hive adapters (`*.g.dart`) are **checked in and hand-edited**, because
`build_runner` cannot be run here. When changing a `@HiveType` model, update
`lib/data/models/*.g.dart` by hand: add the field to `read()` with a null-safe
default (old records lack it), add a `writeByte` line, and bump the field count
at the top of `write()`.

Live typeIds: **1** Subject, **2** Subtopic, **3** Review, **4** Topic. They are
permanent — never renumber or reuse one.

## Watching a CI build

```bash
gh run list --limit 1 --json databaseId,status,conclusion
gh run view <id> --log-failed | grep -iE "error:|Unresolved reference"
```

`gh run watch` has returned exit 0 for *failed* runs — always confirm with
`--json conclusion` rather than trusting the exit code.

**There is no test-only CI path.** The workflow triggers on push to `main`, and
its publish step is unconditional, so `workflow_dispatch` on a branch would
still cut a release. Running the test suite therefore means publishing. If a
change needs verifying without shipping, add a `pull_request`-triggered
workflow that runs `flutter test` and nothing else — don't reach for
`workflow_dispatch`.

## Releases and version numbers

Two numbers, and conflating them is a data-loss bug:

- **`versionName`** (`1.0.0`) is the only one users see. It comes from
  `version:` in `pubspec.yaml` and nowhere else. Bump that line to ship a new
  version.
- **`versionCode`** is an invisible integer tied to `github.run_number`.
  **Never reset it.** Android refuses to install an APK whose code is below the
  installed one, and the only way past that is an uninstall, which wipes
  app-private storage. An earlier scheme derived the *displayed* version from
  the run number and shipped versionCode 2024+ (per-ABI: `abi × 1000 + run`) to
  real phones, so the counter has to keep climbing even though the name
  restarted at 1.0.0.

Releases are tagged `v<versionName>` with `allowUpdates: true`, so **pushing to
`main` without bumping `pubspec.yaml` refreshes the existing release in place**
rather than creating a new one — the version stays put while the APK behind it
changes.

### Verifying a published APK

The APKs use APK Signature Scheme v2 with no `META-INF` block, so
`keytool -printcert -jarfile` prints nothing and `apksigner` isn't installed
here. To confirm two builds share a signing key (the landmine below), parse the
APK Signing Block directly: locate the EOCD, read the central-directory offset,
check for the `APK Sig Block 42` magic immediately before it, walk the
id-value pairs to id `0x7109871a`, and SHA-256 the first certificate. The
manifest is binary XML — `strings` won't find `versionName` because it is
UTF-16; parse the string pool instead.

## The download page

`docs/index.html` is a static page served by GitHub Pages from `main` `/docs`.
It links to `/releases/latest/download/app-arm64-v8a-release.apk`, a URL GitHub
keeps aimed at the newest release, so **the page never needs republishing when a
version ships**. `docs/.nojekyll` stops Jekyll processing the folder — deleting
it breaks the site.

## Architecture

Clean-architecture-lite: `presentation` → `domain` ← `data`, with `services`
owning everything that touches the platform. `README.md` has the full tree.

### 0. The hierarchy is Subject → Topic → Subtopic, and only the leaf is real

A **subtopic** is the only thing with a schedule, a reminder, attachments and
review history. Subjects and topics are grouping layers: no `nextDueAt`, no
ladder, nothing to revise. Every id that anything else keys on — reviews,
`attachments/<id>/`, `RecallDay-files/<id>/`, notification id blocks — is a
subtopic id.

**Two names on disk mean the opposite of what they say, and must stay that way:**

| constant / key | holds | why |
|---|---|---|
| `StorageService.subtopicsBox` = `'topics'` | subtopics | the box has been called that since 1.0.0, when the leaf *was* a topic. A box name is a filename; renaming it orphans every database. |
| `StorageService.topicsBox` = `'topic_groups'` | topics | new box, added with the subtopic layer. It cannot be called `topics`. |
| `ReviewModel` field 1 / JSON `topicId` | subtopic id | the id never changed, so the historical key still points at the right row. Only the Dart identifier moved. |

Adding the subtopic layer **moved no records.** Subtopics kept typeId 2, their
box, their ids and every field; the only addition is field 20 (`topicId`). Each
older record is given a topic of its own, named after it, by
`runHierarchyMigration` in `lib/data/migrations.dart` — which runs at the end of
`StorageService.init()` and again after every restore, is idempotent (it only
touches a subtopic whose `topicId` is missing *or* dangling), and never throws.

Backup JSON is versioned: schema 3 has `topics` (groups) + `subtopics` (leaves);
schema ≤2 has only `topics`, and those entries **are** the leaves.
`restoreFromJson` branches on the presence of the `subtopics` key, then runs the
migration.

### The other five things that require reading several files:

#### 1. Reads and writes are deliberately separate

`presentation/providers/providers.dart` holds **only** derived state
(`dueTodayProvider`, `streakDaysProvider`, …). Every mutation lives in
`topic_commands.dart` — subjects, topics and subtopics alike, despite the file's
name. `providers.dart` re-exports it, so screens import one file. If a change
writes data, schedules a notification, or touches a backup, it belongs in
`TopicCommands`.

`currentDayProvider` is the other thing to know here: it returns today's date
and invalidates itself when the date changes (30-second poll, plus an
`ref.invalidate` on app resume in `main.dart`). `dueTodayProvider` and
`overdueProvider` watch it, which is what makes the Today screen roll over at
**midnight** rather than at each subtopic's reminder hour. `Subtopic.isDue` and
`.isOverdue` are day-granular for the same reason — testing `nextDueAt <= now`
listed a 6am subtopic from midnight but hid its Revise button until 6.

Each mutation follows the same order — **persist, then notify, then back up** —
so a failure in the notification layer can never abandon a half-written change.

#### 2. Hive is app-private; the user's folder is the durable copy

Hive needs a real filesystem path and **cannot live on a SAF tree**, so the
database is internal (deleted on uninstall) and mirrored to a user-chosen folder
after every change:

```
<chosen folder>/
├── recallday-backup.json     — database only; rewritten on every change
└── RecallDay-files/<subtopicId>/<file>  — one copy per attachment, once
```

Raw `/storage/emulated/0/...` paths are **banned**. They were tried and failed
three ways: a write could succeed while the matching read returned `EACCES`,
`File.exists()` returns `false` on a denied read (so a present file looks
absent), and the OS silently rewrote file extensions. The full rationale is at
the top of `backup_service.dart` — read it before touching storage.

#### 3. Attachments are never re-archived

They are immutable once added, so each is streamed into the folder **exactly
once** via `copyIn`. Bundling them into an archive on every change once
allocated ~300MB for 64MB of video (in-memory `Archive` + encoded zip + a
method-channel copy on both sides) and got the process OOM-killed, with the work
on the main isolate causing ANRs.

Rules that follow from this:
- Large files must never cross the method channel as bytes — use
  `copyIn`/`copyOut`, which stream disk-to-disk in 64KB chunks
- `FilePicker` must use `withData: false` and read the path
- Zip work (export/import) streams via `ZipFileEncoder` / `InputFileStream` and
  runs in `Isolate.run`

#### 4. The SAF bridge is a two-layer contract

`lib/services/saf_service.dart` ↔ `MainActivity.kt` over the `recallday/saf`
channel. Changing either side requires changing both. Verify with:

```bash
# every case has an impl, every Dart call has a case, no case is unreachable
grep -oE '"(\w+)" ->' android/app/src/main/kotlin/com/recallday/app/MainActivity.kt
grep -oE "invokeMethod<[^(]*>\('(\w+)'" lib/services/saf_service.dart
```

The SAF layer is **unaffected by the subtopic layer** — it only ever sees paths
and bytes, so `RecallDay-files/<id>/…` kept working because the ids did not
change.

Folder access is granted via `ACTION_OPEN_DOCUMENT_TREE` +
`takePersistableUriPermission`. **That grant does not survive an uninstall** —
Android ties it to the app's install identity, so auto-reconnect after reinstall
is impossible. `pickFolderForImport()` deliberately does *not* persist or store
its URI, so importing from another folder cannot silently relocate the user's
storage location.

#### 5. The scheduling ladder's clamp is load-bearing twice


`SpacedRepetitionEngine` walks `[1, 3, 7, 14, 30]` days and then holds at the
top rung — a revision a month, forever. There is **no plateau branch**; the
plateau *is* `math.min(ladderIndex + advance, ladder.length - 1)`, which parks
on the last rung and keeps returning it. That same clamp absorbs a stale
`ladderIndex` (records saved by an older 7-rung ladder carry values up to 6),
which is why the ladder could change with no Hive migration and why the only
bare `ladder[...]` read is always in range. Rewriting the clamp as a plain
`+ 1` reintroduces both a `RangeError` and unbounded growth.

Two facts that make the file read strangely until you know them:

- **The UI only ever sends `ReviewRating.good`.** `subtopic_detail_page.dart`
  and `markRevisedToday` are the only callers. `easy`/`hard`/`forgot` are
  reachable in tests only, so the four-rating model is retained but dormant.
- **`ease` is still computed, clamped and recorded on every `Review`, but no
  longer affects the interval.** It is kept so difficulty-aware scheduling can
  return without reconstructing the state it needs — don't delete it as dead.

An earlier SM-2 steady state (`interval × ease × ratingMultiplier`) was removed
because, with ease pinned at its 2.5 default by the single-rating UI, it
produced 7 → 18 → 45 → 113 → 282 days. Reminders years out are not reminders.

## Landmines

- **`res/raw/keep.xml` must list every drawable named only from a Dart string.**
  `shrinkResources` strips them otherwise; a missing notification icon made
  `NotificationService.init()` throw before `runApp()`, producing a black screen
  in release only. `main.dart` now guards every startup step for this reason —
  keep it that way.
- **Exact alarms are denied by default on Android 14+** for this app category.
  `zonedSchedule` must fall back to `inexactAllowWhileIdle`; an uncaught
  `exact_alarms_not_permitted` once meant no reminder was ever scheduled.
- **Notification scheduling must never throw into a caller.** Every public
  method in `NotificationService` catches and logs.
- **`Box.clear()` does not fire `box.watch()`.** Delete by key
  (`deleteAll(box.keys.toList())`) or the UI keeps rendering deleted data.
- **`AppCard` accent bars use a `Stack`, not `Row(crossAxisAlignment: stretch)`.**
  Stretch passes an infinite tight height inside a list and paints nothing in
  release — every card row silently vanished.
- **`Subtopic.defaultReminderHour` (6) is for NEW records only.** The `?? 19`
  fallbacks in `SubtopicModel`'s adapter and `fromJson` reconstruct what a
  record written before the field existed was *actually* scheduled at. Changing
  them silently moves every legacy reminder.
- **Releases must stay signed with the same key** (`KEYSTORE_BASE64` /
  `KEYSTORE_PASSWORD` secrets; keystore in the gitignored `.secrets/`). A
  different signature means users must uninstall, which wipes their local data.
- **`versionCode` must never decrease** — see "Releases and version numbers".
  It looks like a tidy-up waiting to happen and is not one.

## Toolchain floors

Each of these was raised to fix a specific build failure; lowering any will
break CI. Flutter ≥ 3.32 (`workmanager`), Gradle 8.14.3, AGP 8.11.1, Kotlin
2.2.20 (Flutter's own minimums), `compileSdk 36` (attachment plugins ship AARs
built against it). `minSdk` stays 24.

## Conventions

- Spacing, radii and motion come from `core/theme/app_tokens.dart`; colours from
  the theme. Never hardcode a status colour — use `StatusColors.success(context)`
  / `.warning(context)`, and `colorScheme.error` for errors.
- Muted text is `colorScheme.onSurfaceVariant`. There is no `textMuted` constant
  — the old one was a fixed dark-theme grey, invisible in light mode.
- `flutter_lints` plus `require_trailing_commas`, `prefer_single_quotes` and
  `always_declare_return_types` (see `analysis_options.yaml`).
