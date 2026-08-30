import 'package:flutter_test/flutter_test.dart';
import 'package:recallday/domain/entities/topic.dart';
import 'package:recallday/domain/usecases/spaced_repetition_engine.dart';

Topic _seed({
  int reps = 0,
  double ease = 2.5,
  int currentInterval = 0,
  int ladderIdx = 0,
}) {
  return Topic(
    id: 't',
    subjectId: 's',
    title: 'x',
    createdAt: DateTime(2024, 1, 1),
    nextDueAt: DateTime(2024, 1, 1, 19),
    repetitions: reps,
    ease: ease,
    currentIntervalDays: currentInterval,
    ladderIndex: ladderIdx,
  );
}

void main() {
  group('SpacedRepetitionEngine — climbing the ladder', () {
    const engine = SpacedRepetitionEngine();
    final ref = DateTime(2024, 1, 1, 12);

    test('first "good" review advances to ladder rung 1 (1 → 3 days)', () {
      final t = _seed(ladderIdx: 0);
      final r = engine.schedule(t, ReviewRating.good, now: ref);
      expect(r.nextLadderIndex, 1);
      expect(r.nextIntervalDays, 3);
      expect(r.nextRepetitions, 1);
    });

    test('"easy" skips one ladder rung', () {
      final t = _seed(ladderIdx: 0);
      final r = engine.schedule(t, ReviewRating.easy, now: ref);
      expect(r.nextLadderIndex, 2);
      expect(r.nextIntervalDays, 7);
    });

    test('"forgot" rewinds to rung 0 and resets repetitions', () {
      final t = _seed(reps: 1, ladderIdx: 2, currentInterval: 7);
      final r = engine.schedule(t, ReviewRating.forgot, now: ref);
      expect(r.nextLadderIndex, 0);
      expect(r.nextIntervalDays, 1);
      expect(r.nextRepetitions, 0);
    });

    test('next due time is anchored to topic reminder hour/minute', () {
      final t = _seed(ladderIdx: 0).copyWith(
        reminderHour: 9, reminderMinute: 30,
      );
      final r = engine.schedule(t, ReviewRating.good, now: ref);
      expect(r.nextDueAt.hour, 9);
      expect(r.nextDueAt.minute, 30);
    });
  });

  group('SpacedRepetitionEngine — monthly plateau (top rung)', () {
    const engine = SpacedRepetitionEngine();
    final ref = DateTime(2024, 1, 1, 12);
    final topRung = SpacedRepetitionEngine.defaultLadder.length - 1;
    final month = SpacedRepetitionEngine.defaultLadder.last;

    test('a review on the top rung stays on it, one month out', () {
      final t = _seed(reps: 4, ladderIdx: topRung, currentInterval: month);
      final r = engine.schedule(t, ReviewRating.good, now: ref);
      expect(r.nextLadderIndex, topRung);
      expect(r.nextIntervalDays, month);
      expect(r.nextRepetitions, 5);
    });

    test('every rating gives the same month once on the plateau', () {
      final t = _seed(reps: 4, ladderIdx: topRung, currentInterval: month);
      for (final rating in [
        ReviewRating.good,
        ReviewRating.hard,
        ReviewRating.easy,
      ]) {
        expect(engine.schedule(t, rating, now: ref).nextIntervalDays, month);
      }
    });

    test('ease is still tracked on the plateau even though it moves nothing',
        () {
      final t = _seed(reps: 4, ease: 2.5, ladderIdx: topRung);
      expect(
        engine.schedule(t, ReviewRating.hard, now: ref).newEase,
        closeTo(2.35, 0.001),
      );
      expect(
        engine.schedule(t, ReviewRating.easy, now: ref).newEase,
        closeTo(2.65, 0.001),
      );
    });

    test('"forgot" from the plateau rewinds to day 1', () {
      final t = _seed(
        reps: 9,
        ease: 1.4,
        ladderIdx: topRung,
        currentInterval: month,
      );
      final r = engine.schedule(t, ReviewRating.forgot, now: ref);
      expect(r.newEase, SpacedRepetitionEngine.easeFloor);
      expect(r.nextLadderIndex, 0);
      expect(r.nextIntervalDays, 1);
      expect(r.nextRepetitions, 0);
    });

    // Topics saved by the old [1,3,7,15,30,60,90] ladder carry an index that is
    // out of range for the current one. The clamp must absorb it rather than
    // throwing, and land the topic on the monthly step.
    test('a stale ladder index from the old ladder lands on the month', () {
      final t = _seed(reps: 6, ladderIdx: 6, currentInterval: 90);
      final r = engine.schedule(t, ReviewRating.good, now: ref);
      expect(r.nextLadderIndex, topRung);
      expect(r.nextIntervalDays, month);
    });
  });

  group('SpacedRepetitionEngine — full schedule', () {
    const engine = SpacedRepetitionEngine();
    final ref = DateTime(2024, 1, 1, 12);

    test('runs 1 → 3 → 7 → 14 → 30 and then holds at one month', () {
      var t = _seed();
      final intervals = <int>[
        engine.initialSchedule(t, now: ref).nextIntervalDays,
      ];
      for (var i = 0; i < 6; i++) {
        final r = engine.schedule(t, ReviewRating.good, now: ref);
        intervals.add(r.nextIntervalDays);
        t = t.copyWith(
          repetitions: r.nextRepetitions,
          ease: r.newEase,
          currentIntervalDays: r.nextIntervalDays,
          ladderIndex: r.nextLadderIndex,
        );
      }
      expect(intervals, [1, 3, 7, 14, 30, 30, 30]);
    });
  });

  group('SpacedRepetitionEngine — invariants', () {
    const engine = SpacedRepetitionEngine();
    final ref = DateTime(2024, 1, 1, 12);

    test('ease is always within [easeFloor, easeCeiling]', () {
      final easies = List.generate(20, (_) =>
          engine.schedule(_seed(reps: 5, ease: 2.99, currentInterval: 30),
              ReviewRating.easy, now: ref));
      for (final r in easies) {
        expect(r.newEase, lessThanOrEqualTo(SpacedRepetitionEngine.easeCeiling));
      }
    });

    // Replaces an older "clamped to <= 730 days" check. Growth is gone, so the
    // invariant is now the ceiling itself: no run of reviews, at any rating,
    // can push an interval past the top rung.
    test('no interval ever exceeds the top rung', () {
      final month = SpacedRepetitionEngine.defaultLadder.last;
      var t = _seed(reps: 5, ease: 3.0);
      for (var i = 0; i < 20; i++) {
        final r = engine.schedule(t, ReviewRating.easy, now: ref);
        t = t.copyWith(
          repetitions: r.nextRepetitions,
          ease: r.newEase,
          currentIntervalDays: r.nextIntervalDays,
          ladderIndex: r.nextLadderIndex,
        );
        expect(r.nextIntervalDays, lessThanOrEqualTo(month));
      }
      expect(t.currentIntervalDays, month);
    });
  });

  group('initialSchedule', () {
    const engine = SpacedRepetitionEngine();

    // The creation day is the first exposure to the material, not a revision.
    // The first revision is therefore one ladder step later, whatever time of
    // day the topic happened to be added.
    test('first revision is one ladder step after the creation day', () {
      final now = DateTime(2024, 6, 1, 9, 0);
      final t = _seed().copyWith(reminderHour: 19, reminderMinute: 0);
      final r = engine.initialSchedule(t, now: now);
      expect(r.nextDueAt, DateTime(2024, 6, 2, 19, 0));
      expect(r.nextIntervalDays, SpacedRepetitionEngine.defaultLadder.first);
    });

    test('time of day the topic was created makes no difference', () {
      final t = _seed().copyWith(reminderHour: 19, reminderMinute: 0);
      final early = engine.initialSchedule(t, now: DateTime(2024, 6, 1, 9, 0));
      final late = engine.initialSchedule(t, now: DateTime(2024, 6, 1, 21, 0));
      expect(early.nextDueAt, late.nextDueAt);
      expect(late.nextDueAt, DateTime(2024, 6, 2, 19, 0));
    });
  });
}
