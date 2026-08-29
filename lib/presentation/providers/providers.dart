import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/subject_repository_impl.dart';
import '../../data/repositories/topic_repository_impl.dart';
import '../../domain/entities/attachment.dart';
import '../../domain/entities/review.dart';
import '../../domain/entities/subject.dart';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/subject_repository.dart';
import '../../domain/repositories/topic_repository.dart';
import '../../domain/usecases/spaced_repetition_engine.dart';
import '../../services/attachment_service.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';

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
    List<Attachment> attachments = const [],
    String? presetId,
  }) async {
    // The create form needs an id up front so attachments can be staged into
    // the topic's folder before it's saved.
    final id = presetId ?? ref.read(uuidProvider).v4();
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
      attachments: attachments,
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
    List<Attachment>? attachments,
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
      attachments: attachments,
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

  /// "I revised this today" — the Home checkbox.
  ///
  /// Records a normal `good` review, so the spaced-repetition ladder advances
  /// and the topic comes back at the next interval. This is deliberately NOT
  /// the same as [stopRepetition]: ticking a day off should not retire a topic.
  ///
  /// Returns the number of days until the topic is next due, so the caller can
  /// tell the user when they'll see it again.
  Future<int> markRevisedToday(String topicId) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return 0;
    final result = ref.read(engineProvider).schedule(t, ReviewRating.good);
    await reviewTopic(topicId, ReviewRating.good);
    return result.nextIntervalDays;
  }

  /// Retire a topic the user has mastered: no further reminders, ever.
  ///
  /// Distinct from pausing — pause is a temporary hold, this is "I know this
  /// now". The topic stays visible inside its subject so the history isn't
  /// lost, and [resumeRepetition] puts it back in rotation.
  Future<void> stopRepetition(String topicId) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;
    await repo.upsert(t.copyWith(status: TopicStatus.completed));
    await NotificationService.instance.cancelForTopic(topicId);
    _backup();
  }

  /// Put a stopped (or paused) topic back into the schedule, due today at its
  /// reminder time.
  Future<void> resumeRepetition(String topicId) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;
    final now = DateTime.now();
    var due = DateTime(
      now.year,
      now.month,
      now.day,
      t.reminderHour,
      t.reminderMinute,
    );
    if (!due.isAfter(now)) due = due.add(const Duration(days: 1));

    final updated = t.copyWith(status: TopicStatus.active, nextDueAt: due);
    await repo.upsert(updated);
    await NotificationService.instance
        .scheduleForTopic(updated, subjectName: _subjectName(updated.subjectId));
    _backup();
  }

  /// Wipe every subject, topic, review and attachment file.
  ///
  /// Uses `deleteAll(keys)` rather than `Box.clear()`: Hive's clear() empties
  /// the box without emitting change events, so `box.watch()` never fired and
  /// the screens kept rendering data that was already gone — the reset looked
  /// like it had done nothing until the app was restarted.
  ///
  /// The automatic snapshot is rewritten afterwards so it reflects the empty
  /// database; otherwise the next launch would offer to restore exactly what
  /// the user just deleted.
  Future<void> resetAll() async {
    await NotificationService.instance.cancelAll();

    final topicRepo = ref.read(topicRepositoryProvider);
    for (final t in topicRepo.all()) {
      await AttachmentService.instance.deleteAllFor(t.id);
    }

    final store = StorageService.instance;
    await store.topics.deleteAll(store.topics.keys.toList());
    await store.subjects.deleteAll(store.subjects.keys.toList());
    await store.reviews.deleteAll(store.reviews.keys.toList());

    await BackupService.instance.flush();
  }

  /// Replace a topic's attachment list (add or remove from the detail page).
  Future<void> setAttachments(
    String topicId,
    List<Attachment> attachments,
  ) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;
    await repo.upsert(t.copyWith(attachments: attachments));
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
    // Attached files live outside Hive, so they'd otherwise sit on disk
    // forever after the topic that referenced them is gone.
    await AttachmentService.instance.deleteAllFor(topicId);
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
      await AttachmentService.instance.deleteAllFor(t.id);
      await NotificationService.instance.cancelForTopic(t.id);
    }
    await subjectRepo.delete(subjectId);
    _backup();
  }
}

final topicCommandsProvider = Provider<TopicCommands>((ref) => TopicCommands(ref));
