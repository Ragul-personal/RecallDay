import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/subject_repository_impl.dart';
import '../../data/repositories/topic_repository_impl.dart';
import '../../domain/entities/subject.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/subject_repository.dart';
import '../../domain/repositories/topic_repository.dart';
import '../../domain/usecases/spaced_repetition_engine.dart';

// Everything here is READ-ONLY: singletons, repositories, and values derived
// from them. All writes live in TopicCommands (topic_commands.dart), which is
// re-exported below so a screen needs a single import for both.

// ---------- core singletons ----------
final uuidProvider = Provider<Uuid>((_) => const Uuid());
final engineProvider =
    Provider<SpacedRepetitionEngine>((_) => const SpacedRepetitionEngine());

// ---------- repositories ----------
final subjectRepositoryProvider =
    Provider<SubjectRepository>((_) => SubjectRepositoryImpl());
final topicRepositoryProvider =
    Provider<TopicRepository>((_) => TopicRepositoryImpl());

// ---------- streams (from Hive watchers) ----------
final subjectsStreamProvider = StreamProvider<List<Subject>>(
  (ref) => ref.watch(subjectRepositoryProvider).watch(),
);
final topicsStreamProvider = StreamProvider<List<Topic>>(
  (ref) => ref.watch(topicRepositoryProvider).watch(),
);

// ---------- derived collections ----------
/// Topics due by end of today, EXCLUDING ones already surfaced under
/// [overdueProvider]. Without the `!t.isOverdue` guard these two lists overlap
/// and the Today page renders the same topic twice — once in each section.
final dueTodayProvider = Provider<List<Topic>>((ref) {
  final all = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return all
      .where((t) =>
          t.status == TopicStatus.active &&
          !t.nextDueAt.isAfter(endOfDay) &&
          !t.isOverdue)
      .toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
});

final overdueProvider = Provider<List<Topic>>((ref) {
  final all = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
  return all.where((t) => t.isOverdue).toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
});

// `upcomingProvider` was removed with the Today screen's "Coming up"
// section: the home screen now shows only what is due today.


/// Reviews recorded today. Drives the Today screen's progress bar.
final reviewedTodayCountProvider = Provider<int>((ref) {
  ref.watch(topicsStreamProvider);
  final now = DateTime.now();
  return ref.watch(topicRepositoryProvider).allReviews().where((r) {
    return r.reviewedAt.year == now.year &&
        r.reviewedAt.month == now.month &&
        r.reviewedAt.day == now.day;
  }).length;
});

final streakDaysProvider = Provider<int>((ref) {
  // Re-runs whenever topics stream pulses (i.e. after each review is recorded).
  ref.watch(topicsStreamProvider);
  final reviews = ref.watch(topicRepositoryProvider).allReviews();
  if (reviews.isEmpty) return 0;
  final byDay = <DateTime>{};
  for (final r in reviews) {
    byDay.add(DateTime(r.reviewedAt.year, r.reviewedAt.month, r.reviewedAt.day));
  }
  var streak = 0;
  var cursor = DateTime.now();
  cursor = DateTime(cursor.year, cursor.month, cursor.day);
  while (byDay.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
});

/// Longest run of consecutive days with at least one revision.
///
/// Worth surfacing next to the current streak: on the day a streak breaks, the
/// current count drops to zero and the only thing left showing progress is the
/// best you have managed.
final bestStreakProvider = Provider<int>((ref) {
  ref.watch(topicsStreamProvider);
  final days = <DateTime>{};
  for (final r in ref.watch(topicRepositoryProvider).allReviews()) {
    days.add(DateTime(r.reviewedAt.year, r.reviewedAt.month, r.reviewedAt.day));
  }
  if (days.isEmpty) return 0;

  final sorted = days.toList()..sort();
  var best = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].difference(sorted[i - 1]).inDays;
    run = gap == 1 ? run + 1 : 1;
    if (run > best) best = run;
  }
  return best;
});

/// Revisions recorded per day for the last [days] days, oldest first.
final recentActivityProvider = Provider<List<int>>((ref) {
  ref.watch(topicsStreamProvider);
  const days = 30;
  final reviews = ref.watch(topicRepositoryProvider).allReviews();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final counts = <DateTime, int>{};
  for (final r in reviews) {
    final d = DateTime(r.reviewedAt.year, r.reviewedAt.month, r.reviewedAt.day);
    counts[d] = (counts[d] ?? 0) + 1;
  }
  return List.generate(
    days,
    (i) => counts[today.subtract(Duration(days: days - 1 - i))] ?? 0,
  );
});

/// Re-exported so widgets can `import providers.dart` and reach both the
/// derived state above and the commands that change it.
export 'topic_commands.dart';
