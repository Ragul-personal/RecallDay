import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../core/theme/app_theme.dart' show BrandColors;

// Hide our domain `Priority` enum — `flutter_local_notifications` exports a
// type with the same name and we use the latter here.
import '../domain/entities/topic.dart' hide Priority;

/// Reliability strategy
/// --------------------
/// Android's notification reliability model has tightened every release:
///   • Doze mode (Android 6+) batches alarms unless `setExactAndAllowWhileIdle`.
///   • Android 12+ requires SCHEDULE_EXACT_ALARM (user-revocable).
///   • Android 13+ requires runtime POST_NOTIFICATIONS permission.
///   • Android 14+ denies SCHEDULE_EXACT_ALARM by default to apps that aren't
///     clocks/calendars — which includes us.
///   • OEMs (Xiaomi/OnePlus/Samsung/Vivo) maintain aggressive kill lists.
///
/// We adopt a layered approach:
///   1. Schedule the *next* due reminder. We try exact
///      (`AndroidScheduleMode.exactAllowWhileIdle`) and **fall back to inexact**
///      when the exact-alarm permission is missing. An inexact reminder that
///      lands within a few minutes of the hour beats no reminder at all, which
///      is what the previous exact-only build produced on Android 13+.
///   2. Also schedule daily "safety re-fire" alarms after the due date; if the
///      user misses today, they're re-prompted tomorrow at the same hour. This
///      is the "persistent reminders" guarantee.
///   3. Re-arm every active topic on app start ([scheduleAllFrom]) and from a
///      periodic WorkManager sweep, so alarms dropped by OEM cleanup come back.
///   4. A boot receiver (registered in AndroidManifest) re-arms alarms after
///      device restart; flutter_local_notifications already ships this.
///
/// Everything here is failure-tolerant on purpose: a notification that can't be
/// posted must never take down the data mutation that triggered it. Callers
/// used to `await` these methods directly inside create/delete flows, so one
/// `PlatformException` aborted the whole operation.
///
/// What we *don't* promise: minute-level precision under aggressive battery
/// optimization. That fight cannot be won by a third-party app on stock
/// Android, and Play policy forbids workarounds that hide foreground services.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  // Channel settings are immutable once Android has created the channel, so a
  // change to importance/sound needs a NEW id to take effect on devices that
  // already ran an older build. `_v2` carries the high-importance + sound
  // configuration that the original channel shipped without.
  static const String _channelId = 'recallday_reviews_v2';
  static const String _channelName = 'Review reminders';
  static const String _channelDesc =
      'Reminders to revise topics on your spaced-repetition schedule.';

  /// Fixed ids for the two daily digests. Well clear of the per-topic id
  /// blocks below (max 99999 * 16 ≈ 1.6M).
  static const int _morningDigestId = 1900000001;
  static const int _eveningDigestId = 1900000002;

  /// Slots reserved per topic: 1 primary + [_followUpDays] daily re-fires.
  static const int _followUpDays = 14;
  static const int _idsPerTopic = 16; // next power of two ≥ 1 + _followUpDays

  static const String _actionDone = 'mark_done';
  static const String _actionSnooze = 'snooze';
  static const String _actionSkip = 'skip';

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Static pointer set during init — taps invoke this to navigate.
  static void Function(String topicId, String? action)? onAction;

  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (e) {
      // Unknown/unmappable zone: fall back to UTC rather than crashing init.
      // Reminder times drift by the UTC offset, but the app still notifies.
      debugPrint('[notifications] timezone lookup failed, using UTC: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    // `ic_stat_recallday` is the RecallDay brain/calendar mark as a transparent
    // monochrome silhouette, generated from Logo.png. Android masks small icons
    // to their alpha channel, so `ic_launcher` (an opaque filled square)
    // renders as a solid white block in the status bar.
    //
    // If that resource can't be resolved we fall back to `ic_launcher` rather
    // than letting init throw. A missing drawable used to be fatal: the throw
    // escaped main() before runApp(), so the whole app opened to a black
    // screen just because a notification icon was absent. res/raw/keep.xml
    // stops the release resource-shrinker stripping them; this is the second
    // line of defence.
    var initialized = false;
    for (final icon in const ['ic_stat_recallday', 'ic_launcher']) {
      try {
        await _fln.initialize(
          InitializationSettings(android: AndroidInitializationSettings(icon)),
          onDidReceiveNotificationResponse: _handleResponse,
          onDidReceiveBackgroundNotificationResponse: _handleResponseBackground,
        );
        initialized = true;
        break;
      } catch (e) {
        debugPrint('[notifications] init with icon "$icon" failed: $e');
      }
    }
    if (!initialized) {
      debugPrint('[notifications] plugin init failed; reminders unavailable');
      return;
    }

    // Create the channel up-front so per-notification scheduling never races
    // channel creation (a real bug we hit in early builds on Pixel 6).
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
    ));

    _initialized = true;
  }

  /// Request POST_NOTIFICATIONS (13+) and SCHEDULE_EXACT_ALARM (12+).
  /// Returns a [PermissionReport] so the UI can explain partial failures.
  ///
  /// Exact-alarm access is *not* fatal: [_scheduleAt] degrades to an inexact
  /// alarm when it's missing. Notification access is fatal — without it Android
  /// silently drops every post.
  Future<PermissionReport> requestPermissions() async {
    var notifGranted = false;
    var exactGranted = false;

    try {
      notifGranted = (await Permission.notification.request()).isGranted;
    } catch (e) {
      debugPrint('[notifications] POST_NOTIFICATIONS request failed: $e');
    }

    try {
      // On Android 12+ this opens the "Alarms & reminders" settings screen
      // rather than a dialog; on Android 14+ it is denied until the user
      // toggles it there by hand.
      exactGranted = (await Permission.scheduleExactAlarm.request()).isGranted;
    } catch (e) {
      debugPrint('[notifications] SCHEDULE_EXACT_ALARM request failed: $e');
    }

    return PermissionReport(
      notificationsGranted: notifGranted,
      exactAlarmGranted: exactGranted,
    );
  }

  /// Current permission state without prompting. Used by Settings to explain
  /// *why* reminders may be arriving late (or not at all).
  Future<PermissionReport> permissionStatus() async {
    var notifGranted = false;
    var exactGranted = false;
    try {
      notifGranted = await Permission.notification.isGranted;
    } catch (_) {}
    try {
      exactGranted = await Permission.scheduleExactAlarm.isGranted;
    } catch (_) {}
    return PermissionReport(
      notificationsGranted: notifGranted,
      exactAlarmGranted: exactGranted,
    );
  }

  /// Post a notification right now. Used by Settings → "Send a test reminder"
  /// so the user can verify the channel end-to-end without waiting for a due
  /// date. Returns false if Android refused the post.
  Future<bool> showTestNotification() async {
    try {
      await init();
      await _fln.show(
        _testId,
        'Test reminder',
        'If you can see this, RecallDay reminders are working.',
        _details(title: 'Test reminder'),
      );
      return true;
    } catch (e) {
      debugPrint('[notifications] test post failed: $e');
      return false;
    }
  }

  /// Schedule the next-due reminder for a single topic, plus daily re-fires.
  ///
  /// Idempotent: cancels this topic's existing notifications first. Never
  /// throws — failures are logged and swallowed so callers can treat scheduling
  /// as best-effort side work.
  ///
  /// [subjectName] is shown in the notification body so the reminder reads
  /// "Operating Systems · Deadlocks" rather than just the bare topic title.
  /// [showOverdueImmediately] posts an already-due topic's reminder right away.
  /// Callers re-arming while the user is actively in the app pass false — the
  /// Today screen is already showing them the same list, and firing a burst of
  /// notifications behind it is just noise.
  Future<void> scheduleForTopic(
    Topic topic, {
    String? subjectName,
    bool showOverdueImmediately = true,
  }) async {
    try {
      await init();
      await cancelForTopic(topic.id);

      if (topic.status != TopicStatus.active) return;

      final now = tz.TZDateTime.now(tz.local);
      final due = tz.TZDateTime.from(topic.nextDueAt, tz.local);
      final base = _idForTopic(topic.id);

      if (due.isAfter(now)) {
        await _scheduleAt(topic, due, base, subjectName);
      } else if (showOverdueImmediately) {
        // Already due/overdue — surface it immediately.
        await _showNow(topic, subjectName);
      }

      if (!topic.persistentReminders) return;

      // Daily re-fire safety net, anchored to the user's reminder time so the
      // follow-ups land at the hour they chose rather than at whatever moment
      // the topic happened to fall due.
      final anchor = due.isAfter(now) ? due : now;
      for (var i = 1; i <= _followUpDays; i++) {
        final day = anchor.add(Duration(days: i));
        final reFire = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          topic.reminderHour,
          topic.reminderMinute,
        );
        if (!reFire.isAfter(now)) continue;
        await _scheduleAt(topic, reFire, base + i, subjectName);
      }
    } catch (e, st) {
      debugPrint('[notifications] scheduleForTopic(${topic.id}) failed: $e\n$st');
    }
  }

  /// Re-arm every active topic. Called on app start and from the WorkManager
  /// sweep — alarms are the first thing OEM battery savers drop.
  ///
  /// [subjectNames] maps subjectId → display name; missing entries just omit
  /// the subject prefix.
  Future<void> scheduleAllFrom(
    List<Topic> topics, {
    Map<String, String> subjectNames = const {},
    bool showOverdueImmediately = true,
  }) async {
    for (final t in topics) {
      if (t.status != TopicStatus.active) continue;
      await scheduleForTopic(
        t,
        subjectName: subjectNames[t.subjectId],
        showOverdueImmediately: showOverdueImmediately,
      );
    }
  }

  /// The two daily summaries: a morning nudge and an evening catch-up.
  ///
  /// These aren't per-topic alarms, so they can't be scheduled once and left —
  /// whether they should fire at all depends on the data at the time. Instead
  /// the next occurrence is (re)scheduled whenever anything changes and on
  /// every app start, and cancelled outright when [count] is zero. That way
  /// the user is never greeted with "you have 0 topics to revise".
  Future<void> scheduleDigest({
    required DigestSlot slot,
    required DateTime when,
    required int count,
  }) async {
    final id = slot == DigestSlot.morning ? _morningDigestId : _eveningDigestId;
    try {
      await init();
      await _fln.cancel(id);
      if (count <= 0) return;

      final plural = count == 1 ? '' : 's';
      final title = slot == DigestSlot.morning
          ? 'Good morning'
          : 'Good evening';
      final body = slot == DigestSlot.morning
          ? 'You have $count topic$plural to revise today. A good time to '
              'start while it is fresh.'
          : '$count revision$plural still waiting today. A few minutes now and '
              'you are done.';

      final scheduled = tz.TZDateTime.from(when, tz.local);
      if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

      final mode = await _preferredScheduleMode();
      try {
        await _fln.zonedSchedule(
          id, title, body, scheduled,
          _details(title: title, body: body),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
          _exactAlarmsAllowed = false;
          await _fln.zonedSchedule(
            id, title, body, scheduled,
            _details(title: title, body: body),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('[notifications] digest ($slot) failed: $e');
    }
  }

  Future<void> cancelForTopic(String topicId) async {
    try {
      await init();
      final base = _idForTopic(topicId);
      for (var i = 0; i <= _followUpDays; i++) {
        await _fln.cancel(base + i);
      }
    } catch (e) {
      debugPrint('[notifications] cancelForTopic($topicId) failed: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await init();
      await _fln.cancelAll();
    } catch (e) {
      debugPrint('[notifications] cancelAll failed: $e');
    }
  }

  // ---------- internal scheduling primitives ----------

  /// Schedule one alarm, preferring exact delivery but degrading to inexact
  /// when the OS withholds SCHEDULE_EXACT_ALARM.
  ///
  /// This is the fix for the "no notifications at all" bug: the previous build
  /// always passed `exactAllowWhileIdle`, and Android 13+/14 throws
  /// `PlatformException(exact_alarms_not_permitted)` for apps without that
  /// (user-granted, off-by-default) permission. The throw escaped into
  /// `createTopic`, so the alarm was never registered *and* the create screen
  /// hung. We now check first and, belt-and-braces, retry inexact on throw.
  Future<void> _scheduleAt(
    Topic topic,
    tz.TZDateTime when,
    int id,
    String? subjectName,
  ) async {
    final mode = await _preferredScheduleMode();
    try {
      await _zonedSchedule(topic, when, id, subjectName, mode);
    } catch (e) {
      // Deliberately catching everything, not just Exception: the platform
      // channel can surface errors as well as exceptions, and a reminder that
      // arrives late is strictly better than one that never arrives.
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        debugPrint('[notifications] exact alarm rejected ($e) — retrying inexact');
        _exactAlarmsAllowed = false;
        await _zonedSchedule(topic, when, id, subjectName,
            AndroidScheduleMode.inexactAllowWhileIdle);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _zonedSchedule(
    Topic topic,
    tz.TZDateTime when,
    int id,
    String? subjectName,
    AndroidScheduleMode mode,
  ) {
    return _fln.zonedSchedule(
      id,
      _titleFor(topic),
      _bodyFor(topic, subjectName),
      when,
      _details(title: _titleFor(topic), body: _bodyFor(topic, subjectName)),
      payload: jsonEncode({'topicId': topic.id}),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _showNow(Topic topic, String? subjectName) async {
    await _fln.show(
      _idForTopic(topic.id),
      _titleFor(topic),
      _bodyFor(topic, subjectName),
      _details(title: _titleFor(topic), body: _bodyFor(topic, subjectName)),
      payload: jsonEncode({'topicId': topic.id}),
    );
  }

  /// Cached so we don't hit the permission channel once per scheduled alarm
  /// (a topic with follow-ups schedules 15 of them in a row).
  bool? _exactAlarmsAllowed;

  Future<AndroidScheduleMode> _preferredScheduleMode() async {
    if (_exactAlarmsAllowed == null) {
      try {
        _exactAlarmsAllowed = await Permission.scheduleExactAlarm.isGranted;
      } catch (_) {
        _exactAlarmsAllowed = false;
      }
    }
    return _exactAlarmsAllowed!
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Drop the cached exact-alarm verdict so the next schedule re-checks it —
  /// call after the user has been sent to the system settings screen.
  void invalidatePermissionCache() => _exactAlarmsAllowed = null;

  /// Open this app's system settings page.
  ///
  /// Android stops showing the permission dialog once a user has denied it
  /// twice, so re-requesting silently does nothing and the only route left is
  /// the settings screen.
  Future<bool> openSystemSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      debugPrint('[notifications] openAppSettings failed: $e');
      return false;
    }
  }

  /// True when Android will no longer prompt for notifications, so the user
  /// has to grant it from settings by hand.
  Future<bool> notificationsPermanentlyDenied() async {
    try {
      return await Permission.notification.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  String _titleFor(Topic t) => 'Revise: ${t.title}';

  /// Body leads with the subject so the notification says *what to study and
  /// where it belongs* at a glance, then appends the note excerpt if present.
  String _bodyFor(Topic t, String? subjectName) {
    final parts = <String>[];
    if (subjectName != null && subjectName.trim().isNotEmpty) {
      parts.add(subjectName.trim());
    }
    final notes = t.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      parts.add(notes.length > 120 ? '${notes.substring(0, 120)}…' : notes);
    } else {
      parts.add(t.isOverdue ? 'Overdue — let’s knock it out' : 'Time to revise');
    }
    return parts.join(' · ');
  }

  NotificationDetails _details({required String title, String? body}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // Heads-up + sound + vibration. These are per-notification hints;
          // the channel (above) is what Android actually enforces, but setting
          // both keeps behaviour consistent across API levels.
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ticker: title,
          // Full-colour logo on the right of the expanded notification, so a
          // reminder is recognisably RecallDay and not just a grey glyph.
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_notification_logo',
          ),
          color: BrandColors.violet,
          colorized: false,
          styleInformation: body == null
              ? null
              : BigTextStyleInformation(body, contentTitle: title),
          groupKey: 'recallday_reviews',
          setAsGroupSummary: false,
          // showsUserInterface=true is intentional. Background-isolate actions
          // can't reliably mutate Hive without re-initializing it; opening the
          // app to TopicDetailPage and replaying the action from query params
          // is simpler, more reliable, and matches user expectations
          // ("tapping Done should open the app and confirm the review").
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(_actionDone, 'Done',
                showsUserInterface: true, cancelNotification: true),
            AndroidNotificationAction(_actionSnooze, 'Snooze 1h',
                showsUserInterface: true, cancelNotification: true),
            AndroidNotificationAction(_actionSkip, 'Skip',
                showsUserInterface: true, cancelNotification: true),
          ],
        ),
      );

  // Well clear of the topic id blocks below (max 99999 * 16 ≈ 1.6M).
  static const int _testId = 2000000000;

  // Stable, collision-free integer id derived from the topic uuid.
  //
  // Each topic owns a block of [_idsPerTopic] consecutive ids (primary +
  // follow-ups). The old scheme used the raw hash and then added 0..7, so two
  // topics whose hashes landed within 7 of each other silently cancelled one
  // another's re-fires.
  int _idForTopic(String topicId) {
    final block = topicId.hashCode.abs() % 100000;
    return block * _idsPerTopic;
  }

  // ---------- response routing ----------

  static void _handleResponse(NotificationResponse r) {
    final topicId = _topicIdFromPayload(r.payload);
    if (topicId == null) return;
    onAction?.call(topicId, r.actionId);
  }

  @pragma('vm:entry-point')
  static void _handleResponseBackground(NotificationResponse r) {
    // Background isolate has no Riverpod context. Tapping the notification
    // brings the app up and [_handleResponse] replays the action there.
    final topicId = _topicIdFromPayload(r.payload);
    if (topicId == null) return;
    debugPrint('background action: ${r.actionId} on $topicId');
  }

  static String? _topicIdFromPayload(String? p) {
    if (p == null || p.isEmpty) return null;
    try {
      final m = jsonDecode(p) as Map<String, dynamic>;
      return m['topicId'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// Which of the two daily summaries a notification is.
enum DigestSlot { morning, evening }

class PermissionReport {
  final bool notificationsGranted;
  final bool exactAlarmGranted;
  const PermissionReport({
    required this.notificationsGranted,
    required this.exactAlarmGranted,
  });

  /// Reminders work at all only if we may post them. Exact alarms just improve
  /// punctuality.
  bool get canNotify => notificationsGranted;
}
