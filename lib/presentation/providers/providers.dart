import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/subject_repository_impl.dart';
import '../../data/repositories/topic_repository_impl.dart';
import '../../domain/entities/review.dart';
import '../../domain/entities/subject.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/subject_repository.dart';
import '../../domain/repositories/topic_repository.dart';
import '../../domain/usecases/spaced_repetition_engine.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';

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

final upcomingProvider = Provider<List<Topic>>((ref) {
  final all = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return all
      .where((t) =>
          t.status == TopicStatus.active && t.nextDueAt.isAfter(endOfDay))
      .toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
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

// ---------- mutations / commands ----------
class TopicCommands {
  TopicCommands(this.ref);
  final Ref ref;

  /// Display name for the topic's subject, used so a reminder reads
  /// "Operating Systems · Deadlocks" instead of a bare topic title.
  String? _subjectName(String subjectId) =>
      ref.read(subjectRepositoryProvider).byId(subjectId)?.name;

  /// Mirror the database to shared storage after anything changes, so an
  /// uninstall/reinstall can bring the data back. Debounced and failure-tolerant.
  void _backup() => BackupService.instance.scheduleAutoBackup();

  /// Re-arm alarms for every active topic. Android drops scheduled alarms on
  /// reboot, app update, and OEM battery sweeps, and the app previously only
  /// ever scheduled at create/edit/review time — so a dropped alarm stayed
  /// dropped. Called on app start and from the WorkManager sweep.
  Future<void> reArmAllNotifications() async {
    final topics = ref.read(topicRepositoryProvider).all();
    final names = {
      for (final s in ref.read(subjectRepositoryProvider).all()) s.id: s.name,
    };
    await NotificationService.instance.scheduleAllFrom(
      topics,
      subjectNames: names,
      // The user is in the app right now; the Today screen already lists what's
      // due, so don't also shower them with notifications for it.
      showOverdueImmediately: false,
    );
  }

  /// Create or update a subject. Routed through here (rather than the repo
  /// directly) so subject edits also trigger a backup.
  Future<void> saveSubject(Subject s) async {
    await ref.read(subjectRepositoryProvider).upsert(s);
    _backup();
  }

  Future<Topic> createTopic({
    required String subjectId,
    required String title,
    String? notes,
    Priority priority = Priority.medium,
    Difficulty difficulty = Difficulty.medium,
    int estimatedMinutes = 15,
    List<String> tags = const [],
    int reminderHour = 19,
    int reminderMinute = 0,
    bool persistentReminders = true,
  }) async {
    final id = ref.read(uuidProvider).v4();
    final now = DateTime.now();
    var topic = Topic(
      id: id,
      subjectId: subjectId,
      title: title,
      notes: notes,
      tags: tags,
      priority: priority,
      difficulty: difficulty,
      estimatedMinutes: estimatedMinutes,
      createdAt: now,
      nextDueAt: now,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
      persistentReminders: persistentReminders,
    );
    final init = ref.read(engineProvider).initialSchedule(topic, now: now);
    topic = topic.copyWith(nextDueAt: init.nextDueAt);
    await ref.read(topicRepositoryProvider).upsert(topic);
    await NotificationService.instance
        .scheduleForTopic(topic, subjectName: _subjectName(subjectId));
    _backup();
    return topic;
  }

  /// Update a topic's user-facing fields. Preserves SR state (ease,
  /// repetitions, ladderIndex, lastReviewedAt). If the reminder time changed,
  /// rolls nextDueAt forward to the new hour/minute on the same calendar day
  /// and re-arms the notification.
  Future<void> updateTopic({
    required String topicId,
    required String subjectId,
    required String title,
    String? notes,
    Priority priority = Priority.medium,
    Difficulty difficulty = Difficulty.medium,
    int estimatedMinutes = 15,
    int reminderHour = 19,
    int reminderMinute = 0,
    bool persistentReminders = true,
  }) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;

    final reminderChanged =
        t.reminderHour != reminderHour || t.reminderMinute != reminderMinute;

    var newDue = t.nextDueAt;
    if (reminderChanged) {
      newDue = DateTime(
        t.nextDueAt.year, t.nextDueAt.month, t.nextDueAt.day,
        reminderHour, reminderMinute,
      );
    }

    final updated = t.copyWith(
      title: title,
      notes: notes,
      priority: priority,
      difficulty: difficulty,
      estimatedMinutes: estimatedMinutes,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
      persistentReminders: persistentReminders,
      nextDueAt: newDue,
    );
    await repo.upsert(updated);
    await NotificationService.instance
        .scheduleForTopic(updated, subjectName: _subjectName(updated.subjectId));
    _backup();
  }

  Future<void> reviewTopic(String topicId, ReviewRating rating) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;

    final result = ref.read(engineProvider).schedule(t, rating);
    final updated = t.copyWith(
      repetitions: result.nextRepetitions,
      ease: result.newEase,
      currentIntervalDays: result.nextIntervalDays,
      ladderIndex: result.nextLadderIndex,
      nextDueAt: result.nextDueAt,
      lastReviewedAt: DateTime.now(),
    );
    await repo.upsert(updated);

    final review = Review(
      id: ref.read(uuidProvider).v4(),
      topicId: t.id,
      reviewedAt: DateTime.now(),
      rating: rating,
      intervalAppliedDays: result.nextIntervalDays,
      easeAfter: result.newEase,
    );
    await repo.recordReview(review);
    await NotificationService.instance
        .scheduleForTopic(updated, subjectName: _subjectName(updated.subjectId));
    _backup();
  }

  Future<void> snoozeTopic(String topicId, Duration by) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;
    final updated = t.copyWith(nextDueAt: DateTime.now().add(by));
    await repo.upsert(updated);
    await NotificationService.instance
        .scheduleForTopic(updated, subjectName: _subjectName(updated.subjectId));
    _backup();
  }

  Future<void> setStatus(String topicId, TopicStatus status) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;
    final updated = t.copyWith(status: status);
    await repo.upsert(updated);
    if (status == TopicStatus.active) {
      await NotificationService.instance.scheduleForTopic(updated,
          subjectName: _subjectName(updated.subjectId));
    } else {
      await NotificationService.instance.cancelForTopic(topicId);
    }
    _backup();
  }

  /// Hard-delete a topic and its review history.
  ///
  /// Order matters: the Hive delete happens FIRST. It used to sit behind an
  /// `await` on the notification cancel, so when the notification plugin threw
  /// (see the exact-alarm bug in [NotificationService]) the delete never ran
  /// and the topic appeared undeletable.
  Future<void> deleteTopic(String topicId) async {
    final repo = ref.read(topicRepositoryProvider);
    await repo.delete(topicId);
    await repo.deleteReviewsForTopic(topicId);
    await NotificationService.instance.cancelForTopic(topicId);
    _backup();
  }

  /// Hard-delete a subject AND every topic in it, with their review history.
  Future<void> deleteSubjectCascading(String subjectId) async {
    final topicRepo = ref.read(topicRepositoryProvider);
    final subjectRepo = ref.read(subjectRepositoryProvider);

    final topics = topicRepo.bySubject(subjectId);
    for (final t in topics) {
      await topicRepo.delete(t.id);
      await topicRepo.deleteReviewsForTopic(t.id);
      await NotificationService.instance.cancelForTopic(t.id);
    }
    await subjectRepo.delete(subjectId);
    _backup();
  }
}

final topicCommandsProvider = Provider<TopicCommands>((ref) => TopicCommands(ref));
