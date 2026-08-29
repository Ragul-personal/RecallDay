import 'dart:math' as math;
import '../entities/topic.dart';

/// Pure scheduling engine. No I/O, no platform calls — fully unit-testable.
///
/// Hybrid policy:
///   • Bootstrap phase (repetitions < 2): walk a fixed Leitner-style ladder.
///     Default: [1, 3, 7, 15, 30, 60, 90] days.
///   • Steady state (repetitions ≥ 2): SM-2-derived
///         next = round(currentInterval * easeFactor * ratingMultiplier)
///   • "Forgot" rating always rewinds to ladder index 0 with a damped ease
///     reduction; we never let ease drop below [easeFloor].
///
/// Why hybrid? Pure SM-2 needs ≥1 successful review to compute meaningful
/// next intervals; for a brand-new topic we want the explicit "1d → 3d → 7d"
/// the user expects. Hybrid lets us honor user-chosen ladders while still
/// getting adaptive lengthening for well-known topics.
class SpacedRepetitionEngine {
  static const List<int> defaultLadder = [1, 3, 7, 15, 30, 60, 90];

  static const double easeFloor = 1.3;
  static const double easeCeiling = 3.0;
  static const double easyBonus = 1.30;
  static const double hardPenalty = 0.85;

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
    } else if (topic.repetitions < 2) {
      // Bootstrap: advance one rung on the ladder. "Easy" skips a rung.
      final advance = rating == ReviewRating.easy ? 2 : 1;
      nextLadderIndex = math.min(topic.ladderIndex + advance, ladder.length - 1);
      nextIntervalDays = ladder[nextLadderIndex];
      nextRepetitions = topic.repetitions + 1;
    } else {
      // Steady state: SM-2 multiplicative growth.
      final base = topic.currentIntervalDays > 0
          ? topic.currentIntervalDays
          : ladder.last;
      final mult = switch (rating) {
        ReviewRating.easy => newEase * easyBonus,
        ReviewRating.good => newEase,
        ReviewRating.hard => newEase * hardPenalty,
        ReviewRating.forgot => 1.0, // unreachable, handled above
      };
      nextIntervalDays = (base * mult).round().clamp(1, 365 * 2);
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
  /// We schedule the FIRST reminder for "today at the user's reminder time"
  /// if that's still in the future, otherwise tomorrow.
  ScheduleResult initialSchedule(Topic topic, {DateTime? now}) {
    final nowTs = now ?? DateTime.now();
    var due = _anchorToReminderTime(
      DateTime(nowTs.year, nowTs.month, nowTs.day),
      topic.reminderHour,
      topic.reminderMinute,
    );
    if (!due.isAfter(nowTs)) {
      due = due.add(const Duration(days: 1));
    }
    return ScheduleResult(
      nextDueAt: due,
      nextIntervalDays: 0,
      nextLadderIndex: 0,
      nextRepetitions: 0,
      newEase: topic.ease,
    );
  }

  /// Projected future due dates for a topic, walked optimistically along the
  /// ladder (assumes every review is "good" and on time).
  ///
  /// IMPORTANT: these are display-only projections, not real schedules. After
  /// each actual review the engine recomputes [Topic.nextDueAt] adaptively
  /// using SM-2 ease, so dates beyond the first will shift in practice.
  /// Used by the calendar view to show the user "what their plan looks like".
  ///
  /// Returns at most [count] entries, including the current [topic.nextDueAt]
  /// as the first entry. For a fresh topic (ladderIndex=0, default ladder),
  /// the projection is roughly: today, +3d, +10d, +25d, +55d, +115d, +205d.
  List<DateTime> projectFutureDueDates(Topic topic, {int count = 8}) {
    if (topic.status != TopicStatus.active) return const [];
    final dates = <DateTime>[topic.nextDueAt];
    var anchor = topic.nextDueAt;
    var idx = topic.ladderIndex;
    while (dates.length < count && idx + 1 < ladder.length) {
      idx++;
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
