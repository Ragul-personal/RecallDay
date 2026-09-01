import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/subject_repository_impl.dart';
import '../../data/repositories/subtopic_repository_impl.dart';
import '../../data/repositories/topic_repository_impl.dart';
import '../../domain/entities/subject.dart';
import '../../domain/entities/subtopic.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/subject_repository.dart';
import '../../domain/repositories/subtopic_repository.dart';
import '../../domain/repositories/topic_repository.dart';
import '../../domain/usecases/spaced_repetition_engine.dart';

/// Re-exported so a screen can `import providers.dart` and reach both the
/// derived state below and the commands that change it.
export 'topic_commands.dart';

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
final subtopicRepositoryProvider =
    Provider<SubtopicRepository>((_) => SubtopicRepositoryImpl());

// ---------- streams (from Hive watchers) ----------
final subjectsStreamProvider = StreamProvider<List<Subject>>(
  (ref) => ref.watch(subjectRepositoryProvider).watch(),
);
final topicsStreamProvider = StreamProvider<List<Topic>>(
  (ref) => ref.watch(topicRepositoryProvider).watch(),
);
final subtopicsStreamProvider = StreamProvider<List<Subtopic>>(
  (ref) => ref.watch(subtopicRepositoryProvider).watch(),
);

// ---------- the calendar day ----------

/// Today's date, invalidated the moment the date changes.
///
/// Everything the Today screen shows is a question about *the day*, not the
/// hour: a subtopic due at 6am is today's work from 00:00. Those lists were
/// computed once from `DateTime.now()` at build time, so an app left open
/// across midnight kept showing yesterday's — and, worse, the new day's
/// subtopics didn't appear until something else happened to rebuild.
///
/// A 30-second poll rather than a timer aimed at midnight: a single long timer
/// is the thing Android is most likely to drift or drop while the process is
/// backgrounded, and the check is a couple of integer comparisons. `main.dart`
/// also invalidates this on resume, which covers the case where the process was
/// frozen through midnight entirely.
final currentDayProvider = Provider<DateTime>((ref) {
  final day = startOfDay(DateTime.now());
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (startOfDay(DateTime.now()) != day) ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  return day;
});

DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime endOfDay(DateTime t) =>
    DateTime(t.year, t.month, t.day, 23, 59, 59, 999);

// ---------- lookups ----------

/// Subject and topic by id, for the three-line cards on Today and Calendar.
///
/// Built once per change instead of a `firstWhere` per row: the Today list
/// needs both names for every card it draws, and a linear scan per card turns
/// a long day into quadratic work.
final subjectsByIdProvider = Provider<Map<String, Subject>>((ref) {
  final all = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  return {for (final s in all) s.id: s};
});

final topicsByIdProvider = Provider<Map<String, Topic>>((ref) {
  final all = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
  return {for (final t in all) t.id: t};
});

// ---------- derived collections ----------

/// Topics inside one subject, alphabetically.
final topicsForSubjectProvider =
    Provider.family<List<Topic>, String>((ref, subjectId) {
  final all = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
  return all.where((t) => t.subjectId == subjectId).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
});

/// Subtopics inside one topic, soonest-due first.
final subtopicsForTopicProvider =
    Provider.family<List<Subtopic>, String>((ref, topicId) {
  final all = ref.watch(subtopicsStreamProvider).valueOrNull ?? const [];
  return all.where((s) => s.topicId == topicId).toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
});

/// Every subtopic under a subject, whichever topic it sits in. Used for the
/// counts on the subject list and the progress bars on the Progress tab.
final subtopicsForSubjectProvider =
    Provider.family<List<Subtopic>, String>((ref, subjectId) {
  final all = ref.watch(subtopicsStreamProvider).valueOrNull ?? const [];
  return all.where((s) => s.subjectId == subjectId).toList();
});

/// Subtopics falling due today, EXCLUDING anything already surfaced under
/// [overdueProvider]. The two predicates partition on the same boundary —
/// today's midnight — because without that these lists overlap and the Today
/// page renders the same subtopic twice, once in each section.
///
/// Both are day-granular and both watch [currentDayProvider], so the whole
/// screen rolls over at midnight rather than at each subtopic's reminder hour.
final dueTodayProvider = Provider<List<Subtopic>>((ref) {
  final all = ref.watch(subtopicsStreamProvider).valueOrNull ?? const [];
  final today = ref.watch(currentDayProvider);
  final end = endOfDay(today);
  return all
      .where((s) =>
          s.status == SubtopicStatus.active &&
          !s.nextDueAt.isAfter(end) &&
          !s.nextDueAt.isBefore(today))
      .toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
});

final overdueProvider = Provider<List<Subtopic>>((ref) {
  final all = ref.watch(subtopicsStreamProvider).valueOrNull ?? const [];
  final today = ref.watch(currentDayProvider);
  return all
      .where((s) =>
          s.status == SubtopicStatus.active && s.nextDueAt.isBefore(today))
      .toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
});

// `upcomingProvider` was removed with the Today screen's "Coming up"
// section: the home screen now shows only what is due today.


/// Reviews recorded today. Drives the Today screen's progress bar.
final reviewedTodayCountProvider = Provider<int>((ref) {
  ref.watch(subtopicsStreamProvider);
  final today = ref.watch(currentDayProvider);
  return ref.watch(subtopicRepositoryProvider).allReviews().where((r) {
    return startOfDay(r.reviewedAt) == today;
  }).length;
});

final streakDaysProvider = Provider<int>((ref) {
  // Re-runs whenever the subtopics stream pulses (i.e. after each review is
  // recorded) and when the date rolls over.
  ref.watch(subtopicsStreamProvider);
  final today = ref.watch(currentDayProvider);
  final reviews = ref.watch(subtopicRepositoryProvider).allReviews();
  if (reviews.isEmpty) return 0;
  final byDay = <DateTime>{for (final r in reviews) startOfDay(r.reviewedAt)};
  var streak = 0;
  var cursor = today;
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
  ref.watch(subtopicsStreamProvider);
  final days = <DateTime>{
    for (final r in ref.watch(subtopicRepositoryProvider).allReviews())
      startOfDay(r.reviewedAt),
  };
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
  ref.watch(subtopicsStreamProvider);
  const days = 30;
  final reviews = ref.watch(subtopicRepositoryProvider).allReviews();
  final today = ref.watch(currentDayProvider);

  final counts = <DateTime, int>{};
  for (final r in reviews) {
    final d = startOfDay(r.reviewedAt);
    counts[d] = (counts[d] ?? 0) + 1;
  }
  return List.generate(
    days,
    (i) => counts[today.subtract(Duration(days: days - 1 - i))] ?? 0,
  );
});
