# Notification Reliability — Honest Write-up

The user brief said reminders must "never disappear permanently until the user marks the topic completed or paused." This document explains how close we can actually get to that promise on stock Android, what compromises ship in v1, and what would be required to do better.

## The Android constraints

| Layer | Constraint | What it means |
|---|---|---|
| Doze (Android 6+) | Batches all alarms to 9-min minimum windows when device is unused | `setRepeating` is no longer reliable to the minute |
| Standby buckets (8+) | Per-app job-execution quotas | Background work is throttled by usage frequency |
| Background limits (8+) | No implicit broadcasts; foreground services flagged | We can't run a sticky service quietly |
| `SCHEDULE_EXACT_ALARM` (12+) | Runtime permission, user-revocable | Exact alarms need it; we degrade gracefully without it |
| Exact alarms (14+) | **Denied by default** for non-clock/calendar apps | A "study reminder" app does not qualify — assume it's off |
| `POST_NOTIFICATIONS` (13+) | Runtime permission | Without this, we can't show anything |
| OEM "battery savers" | Out of spec — Xiaomi, OnePlus, Samsung kill alarms by app | No clean fix; we expose a settings shortcut |

## The bug that made v1 silent

v1 passed `AndroidScheduleMode.exactAllowWhileIdle` unconditionally. On Android 13+ — and *always* on 14+, where the permission is off by default for our app category — `zonedSchedule` throws `PlatformException(exact_alarms_not_permitted)`. Nothing caught it, so:

- no alarm was ever registered, and
- because `TopicCommands.createTopic` awaited the scheduling call, the exception propagated into the create-topic screen, which then never popped.

The lesson encoded in `NotificationService` now: **notification scheduling is best-effort side work and must never be able to fail a data mutation.** Every public method there catches and logs rather than throwing.

## Our layered strategy

1. **Primary**: `flutter_local_notifications.zonedSchedule` at the user-chosen hour/minute in their local timezone. We check `SCHEDULE_EXACT_ALARM` first and pick `exactAllowWhileIdle` or `inexactAllowWhileIdle` accordingly, then retry inexact if the exact call throws anyway. A reminder a few minutes late beats no reminder.
2. **Daily safety net**: when `persistentReminders` is true, we schedule a chain of 14 daily re-fires anchored to the user's reminder time. If the user dismisses without acting, they're reminded again the next day. This is the practical implementation of "keep reminding until completed". Each topic owns a 16-wide block of notification ids so neighbouring topics can't cancel each other's re-fires (the old scheme used `hash + 0..7` and collided).
3. **Boot recovery**: `flutter_local_notifications` ships its own `BOOT_COMPLETED` receiver (registered in `AndroidManifest.xml`), which re-registers all pending alarms with the OS after a reboot.
4. **App-start re-arm**: every cold start re-arms all active topics (`TopicCommands.reArmAllNotifications`). Previously alarms were only ever written at create/edit/review time, so anything the OS dropped stayed dropped indefinitely.
5. **Daily sweep**: a WorkManager periodic task (`scheduler_worker.dart`, 12-hour cadence) re-arms alarms for all active topics. Note that this had *never run*: `AndroidManifest.xml` stripped `androidx.work.WorkManagerInitializer` with `tools:node="remove"` without supplying a custom `Configuration.Provider`, so `Workmanager().initialize()` threw on every launch and `main.dart` swallowed it. The initializer is restored.
6. **Channel created at init**: we never schedule into a not-yet-existent channel — that's a real bug we hit on Pixel 6 in early prototyping. Note that channel settings are immutable after creation, so raising importance required a new channel id (`recallday_reviews_v2`).
7. **Legible small icon**: the small icon is `ic_stat_recall`, a transparent monochrome silhouette. Android masks small icons to their alpha channel, so the previous `ic_launcher` (an opaque filled square) rendered as a solid white block.

## What we cannot guarantee

- **Minute-level precision** under aggressive Doze + standby. Worst case: ~15-minute drift on stock Android, more on aggressive OEMs.
- **Survival of long battery saver sessions** on Xiaomi MIUI 14+, OnePlus OxygenOS, Samsung One UI without the user adding RecallDay to the "no battery optimization" list.
- **Notification delivery while the device is in airplane mode** — Firebase isn't involved (we use local notifications), so this works, but anything that requires sync won't.

## What we recommend the user do

After first launch, the app prompts the user to grant `POST_NOTIFICATIONS` and `SCHEDULE_EXACT_ALARM`. Settings now shows the **live permission state** and explains the consequence of each gap, plus:

- **Send a test reminder** — posts immediately, so the notification bar and sound can be verified without waiting for a due date.
- **Re-arm all reminders** — reschedules every active topic on demand.
- **Grant permissions** — reopens the system screens and re-arms afterwards with the upgraded capability.

If reminders are arriving but late, the missing piece is almost always "Alarms & reminders" (`SCHEDULE_EXACT_ALARM`) under Android Settings → Apps → RecallDay. If they aren't arriving at all, it's `POST_NOTIFICATIONS` or an OEM battery optimizer.

## What would improve this in v2

- **A native foreground service** with `dataSync` foreground type, displaying a low-importance ongoing notification while it sweeps the queue. This is the most reliable Android primitive but is regulated under Play policy — your data-safety form must justify it.
- **Push-via-Firebase fallback**: a Cloud Function triggered by Firestore TTL writes a high-priority FCM message to the device at the due time. This bypasses local AlarmManager entirely and is the technique used by Google Calendar / WhatsApp. Cost: small Firebase invoice, plus you must avoid being flagged for misusing high-priority FCM (Google enforces this).
- **CRDT-based sync** so concurrent device writes merge cleanly.

These are deliberately deferred from v1 to keep the surface area small and Play review fast.
