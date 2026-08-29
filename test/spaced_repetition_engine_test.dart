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
  group('SpacedRepetitionEngine — bootstrap (reps < 2)', () {
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

  group('SpacedRepetitionEngine — steady state (reps ≥ 2)', () {
    const engine = SpacedRepetitionEngine();
    final ref = DateTime(2024, 1, 1, 12);

    test('"good" multiplies current interval by ease', () {
      final t = _seed(reps: 2, ease: 2.5, currentInterval: 7);
      final r = engine.schedule(t, ReviewRating.good, now: ref);
      expect(r.nextIntervalDays, (7 * 2.5).round()); // 18
      expect(r.newEase, closeTo(2.5, 0.001));
    });

    test('"hard" applies ease - 0.15 and a hard penalty', () {
      final t = _seed(reps: 2, ease: 2.5, currentInterval: 10);
      final r = engine.schedule(t, ReviewRating.hard, now: ref);
      expect(r.newEase, closeTo(2.35, 0.001));
      // 10 * 2.35 * 0.85 ≈ 19.97 → 20
      expect(r.nextIntervalDays, 20);
    });

    test('"easy" applies easy bonus', () {
      final t = _seed(reps: 2, ease: 2.5, currentInterval: 10);
      final r = engine.schedule(t, ReviewRating.easy, now: ref);
      // ease + 0.15 = 2.65; 10 * 2.65 * 1.30 = 34.45 → 34
      expect(r.newEase, closeTo(2.65, 0.001));
      expect(r.nextIntervalDays, 34);
    });

    test('"forgot" resets ladder + drops ease but stays above floor', () {
      final t = _seed(reps: 5, ease: 1.4, currentInterval: 60);
      final r = engine.schedule(t, ReviewRating.forgot, now: ref);
      expect(r.newEase, SpacedRepetitionEngine.easeFloor);
      expect(r.nextLadderIndex, 0);
      expect(r.nextIntervalDays, 1);
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

    test('intervals are clamped to <= 730 days', () {
      var t = _seed(reps: 5, ease: 3.0, currentInterval: 365);
      for (var i = 0; i < 5; i++) {
        final r = engine.schedule(t, ReviewRating.easy, now: ref);
        t = t.copyWith(
          repetitions: r.nextRepetitions,
          ease: r.newEase,
          currentIntervalDays: r.nextIntervalDays,
        );
        expect(r.nextIntervalDays, lessThanOrEqualTo(730));
      }
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
