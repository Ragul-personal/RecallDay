import 'dart:math' as math;
import '../entities/topic.dart';

/// Pure scheduling engine. No I/O, no platform calls — fully unit-testable.
///
/// Policy: walk a fixed Leitner-style ladder, then hold.
///   • Default ladder: [1, 3, 7, 14, 30] days — the first month is a ramp.
///   • The top rung is a *plateau*, not a stop. Once a topic reaches it, every
///     later revision falls one more month out; intervals never grow past it.
///   • "Forgot" rewinds to ladder index 0 with a damped ease reduction; ease
///     never drops below [easeFloor].
///
/// The plateau falls out of the clamp in [schedule] rather than needing a
/// branch of its own: `math.min(index + advance, ladder.length - 1)` parks on
/// the last rung and keeps returning it.
///
/// This replaced an SM-2 steady state (`interval × ease × ratingMultiplier`,
/// capped at 730 days). Because the UI records a single neutral "Done", every
/// real review arrived as `good` with ease pinned at its 2.5 default, so that
/// phase only ever produced 7 → 18 → 45 → 113 → 282 days — revisions drifting
/// years apart, which is not what a reminder app is for. Ease is still tracked
/// and recorded on every review, so difficulty-aware scheduling can come back
/// without reconstructing the state it needs.
class SpacedRepetitionEngine {
  static const List<int> defaultLadder = [1, 3, 7, 14, 30];

  static const double easeFloor = 1.3;
  static const double easeCeiling = 3.0;

  final List<int> ladder;

  // Note: we'd love to assert(ladder.isNotEmpty) at construction time, but
  // Dart const constructors can't evaluate `.length`/`.isNotEmpty` on a
  // parameter list literal at compile time. The default `defaultLadder` is
  // non-empty, and the only public callers pass empty lists in tests we
  // don't ship, so a runtime guard would be redundant.
  const SpacedRepetitionEngine({this.ladder = defaultLadder});

  /// Compute the new SR state after a review. `now` is injected for testability.
  ScheduleResult schedule(Topic topic, ReviewRating rating, {DateTime? now}) {
    final nowTs = now ?? DateTime.now();

    // 1) Update ease using SM-2's quality-of-recall heuristic.
    //    SM-2 uses q ∈ {0..5}; we map our 4-button rating to comparable deltas.
    final newEase = _updateEase(topic.ease, rating);

    // 2) Compute next interval.
    int nextIntervalDays;
    int nextLadderIndex = topic.ladderIndex;
    int nextRepetitions = topic.repetitions;

    if (rating == ReviewRating.forgot) {
      // Reset ladder; preserve attenuated ease.
      nextLadderIndex = 0;
      nextRepetitions = 0;
      nextIntervalDays = ladder.first;
    } else {
      // Advance one rung. "Easy" skips a rung. The clamp is what creates the
      // monthly plateau: once on the last rung it returns that rung forever.
      //
      // It also absorbs a stale index. Topics written by the old 7-rung ladder
      // carry a ladderIndex of up to 6, so the read below would otherwise be
      // out of range; clamped, such a topic simply lands on the monthly step.
      final advance = rating == ReviewRating.easy ? 2 : 1;
      nextLadderIndex = math.min(topic.ladderIndex + advance, ladder.length - 1);
      nextIntervalDays = ladder[nextLadderIndex];
      nextRepetitions = topic.repetitions + 1;
    }

    // 3) Anchor next due time to user's preferred reminder hour/minute.
    final dueDate = _anchorToReminderTime(
      DateTime(nowTs.year, nowTs.month, nowTs.day)
          .add(Duration(days: nextIntervalDays)),
      topic.reminderHour,
      topic.reminderMinute,
    );

    return ScheduleResult(
      nextDueAt: dueDate,
      nextIntervalDays: nextIntervalDays,
      nextLadderIndex: nextLadderIndex,
      nextRepetitions: nextRepetitions,
      newEase: newEase,
    );
  }

  /// First-time scheduling for a freshly created topic.
  ///
  /// The first revision lands one full ladder step after the day the topic was
  /// created — `ladder.first`, normally tomorrow — not on the creation day.
  ///
  /// It used to schedule for *today* whenever the reminder hour hadn't passed
  /// yet, which quietly made the creation day an extra revision day the ladder
  /// never asked for: a topic added at 9am was due at 7pm the same evening,
  /// then again the next day. You have just studied the material — that IS the
  /// first exposure — so the first *revision* belongs on the next rung.
  ScheduleResult initialSchedule(Topic topic, {DateTime? now}) {
    final nowTs = now ?? DateTime.now();
    final firstStep = ladder.isEmpty ? 1 : ladder.first;
    final due = _anchorToReminderTime(
      DateTime(nowTs.year, nowTs.month, nowTs.day)
          .add(Duration(days: firstStep)),
      topic.reminderHour,
      topic.reminderMinute,
    );
    return ScheduleResult(
      nextDueAt: due,
      nextIntervalDays: firstStep,
      nextLadderIndex: 0,
      nextRepetitions: 0,
      newEase: topic.ease,
    );
  }

  /// Projected future due dates for a topic, walked along the ladder (assumes
  /// every review happens on time).
  ///
  /// IMPORTANT: these are display-only projections, not real schedules — the
  /// calendar view uses them to show the user "what their plan looks like". A
  /// "forgot" rewinds to the first rung, so they are a best case.
  ///
  /// Returns [count] entries, including the current [topic.nextDueAt] as the
  /// first. For a fresh topic on the default ladder: due date, +3d, +7d, +14d,
  /// then one every 30 days.
  ///
  /// The walk continues on the top rung instead of stopping at the end of the
  /// ladder. Stopping would leave a topic that had reached the monthly step
  /// projecting a single date, and the calendar ahead of it empty.
  List<DateTime> projectFutureDueDates(Topic topic, {int count = 8}) {
    if (topic.status != TopicStatus.active || count <= 0) return const [];
    final dates = <DateTime>[topic.nextDueAt];
    var anchor = topic.nextDueAt;
    // Clamped: topics written by the old 7-rung ladder carry a stale index.
    var idx = math.min(topic.ladderIndex, ladder.length - 1);
    while (dates.length < count) {
      idx = math.min(idx + 1, ladder.length - 1);
      anchor = DateTime(anchor.year, anchor.month, anchor.day,
              topic.reminderHour, topic.reminderMinute)
          .add(Duration(days: ladder[idx]));
      dates.add(anchor);
    }
    return dates;
  }

  double _updateEase(double current, ReviewRating r) {
    // Anki/SM-2 ease deltas (reformulated for 4-button rating).
    final delta = switch (r) {
      ReviewRating.easy   =>  0.15,
      ReviewRating.good   =>  0.00,
      ReviewRating.hard   => -0.15,
      ReviewRating.forgot => -0.20,
    };
    final next = current + delta;
    return next.clamp(easeFloor, easeCeiling);
  }

  DateTime _anchorToReminderTime(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);
}

class ScheduleResult {
  final DateTime nextDueAt;
  final int nextIntervalDays;
  final int nextLadderIndex;
  final int nextRepetitions;
  final double newEase;

  const ScheduleResult({
    required this.nextDueAt,
    required this.nextIntervalDays,
    required this.nextLadderIndex,
    required this.nextRepetitions,
    required this.newEase,
  });
}
