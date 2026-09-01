import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/attachment.dart';
import '../../domain/entities/review.dart';
import '../../domain/entities/subject.dart';
import '../../domain/entities/subtopic.dart';
import '../../domain/entities/topic.dart';
import '../../services/attachment_service.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import 'providers.dart';

/// Every write in the app — subjects, topics and subtopics alike.
///
/// Split out of providers.dart, which had grown to mix the read side (derived
/// state) with ~400 lines of mutations. Keeping them apart makes the boundary
/// obvious: if it changes data, schedules a notification or touches a backup,
/// it belongs here.
///
/// Each mutation follows the same shape — persist first, then schedule
/// notifications, then back up — so a failure in the notification layer can
/// never abandon a half-written change.
class TopicCommands {
  TopicCommands(this.ref);
  final Ref ref;

  /// Display names for the two layers above a subtopic, used so a reminder
  /// reads "Operating Systems · Deadlocks · Coffman conditions" rather than a
  /// bare leaf title.
  String? _subjectName(String subjectId) =>
      ref.read(subjectRepositoryProvider).byId(subjectId)?.name;

  String? _topicName(String topicId) =>
      ref.read(topicRepositoryProvider).byId(topicId)?.title;

  /// Re-arm one subtopic's alarms with its subject and topic names attached.
  Future<void> _reschedule(Subtopic s) => NotificationService.instance
      .scheduleForSubtopic(
        s,
        subjectName: _subjectName(s.subjectId),
        topicName: _topicName(s.topicId),
      );

  /// Mirror the database after anything changes, and re-evaluate the two daily
  /// summaries — whether they should fire at all depends on what's due.
  void _backup() {
    BackupService.instance.scheduleAutoBackup();
    unawaited(refreshDailyDigests());
  }

  /// Re-arm the 6am and 8pm summaries for their next occurrence.
  ///
  /// Both are cancelled when nothing is outstanding, so the user is never told
  /// they have zero subtopics to revise. They're recomputed after every change
  /// and on app start rather than scheduled once, because "is there anything to
  /// say?" is only answerable from the data as it stands.
  Future<void> refreshDailyDigests() async {
    final subtopics = ref
        .read(subtopicRepositoryProvider)
        .all()
        .where((s) => s.status == SubtopicStatus.active)
        .toList();

    final now = DateTime.now();
    DateTime nextAt(int hour) {
      final today = DateTime(now.year, now.month, now.day, hour);
      return today.isAfter(now) ? today : today.add(const Duration(days: 1));
    }

    final morning = nextAt(6);
    final evening = nextAt(20);

    // Morning: everything scheduled for that whole day.
    final endOfMorningDay =
        DateTime(morning.year, morning.month, morning.day, 23, 59, 59);
    final morningCount =
        subtopics.where((s) => !s.nextDueAt.isAfter(endOfMorningDay)).length;

    // Evening: only what is still outstanding by 8pm. Revising pushes
    // nextDueAt forward, so anything still due at that moment is unfinished.
    final eveningCount =
        subtopics.where((s) => !s.nextDueAt.isAfter(evening)).length;

    await NotificationService.instance.scheduleDigest(
      slot: DigestSlot.morning,
      when: morning,
      count: morningCount,
    );
    await NotificationService.instance.scheduleDigest(
      slot: DigestSlot.evening,
      when: evening,
      count: eveningCount,
    );
  }

  /// Re-arm alarms for every active subtopic. Android drops scheduled alarms on
  /// reboot, app update, and OEM battery sweeps, and the app previously only
  /// ever scheduled at create/edit/review time — so a dropped alarm stayed
  /// dropped. Called on app start and from the WorkManager sweep.
  Future<void> reArmAllNotifications() async {
    final subtopics = ref.read(subtopicRepositoryProvider).all();
    final subjectNames = {
      for (final s in ref.read(subjectRepositoryProvider).all()) s.id: s.name,
    };
    final topicNames = {
      for (final t in ref.read(topicRepositoryProvider).all()) t.id: t.title,
    };
    await NotificationService.instance.scheduleAllFrom(
      subtopics,
      subjectNames: subjectNames,
      topicNames: topicNames,
      // The user is in the app right now; the Today screen already lists what's
      // due, so don't also shower them with notifications for it.
      showOverdueImmediately: false,
    );
    await refreshDailyDigests();
  }

  // ------------------------------------------------------------------ subject

  /// Create or update a subject. Routed through here (rather than the repo
  /// directly) so subject edits also trigger a backup.
  Future<void> saveSubject(Subject s) async {
    await ref.read(subjectRepositoryProvider).upsert(s);
    _backup();
  }

  /// Hard-delete a subject AND every topic and subtopic in it, with their
  /// review history.
  Future<void> deleteSubjectCascading(String subjectId) async {
    final topicRepo = ref.read(topicRepositoryProvider);
    final subjectRepo = ref.read(subjectRepositoryProvider);

    for (final t in topicRepo.bySubject(subjectId)) {
      await _deleteTopicInner(t.id);
    }
    // Belt and braces: a subtopic whose topic went missing at some point would
    // otherwise survive its own subject's deletion and haunt the Today screen.
    for (final s in ref.read(subtopicRepositoryProvider).bySubject(subjectId)) {
      await _deleteSubtopicInner(s.id);
    }
    await subjectRepo.delete(subjectId);
    _backup();
  }

  // -------------------------------------------------------------------- topic

  /// Create a topic — a grouping inside a subject. Carries no schedule of its
  /// own; the subtopics added under it do.
  Future<Topic> createTopic({
    required String subjectId,
    required String title,
  }) async {
    final topic = Topic(
      id: ref.read(uuidProvider).v4(),
      subjectId: subjectId,
      title: title,
      createdAt: DateTime.now(),
    );
    await ref.read(topicRepositoryProvider).upsert(topic);
    _backup();
    return topic;
  }

  /// Rename a topic, or move it to another subject.
  ///
  /// Subtopics carry a denormalised `subjectId`, so a move has to rewrite every
  /// child and re-arm its reminder — the subject's name is in the notification
  /// body, and its colour is on every card. Leaving the children behind would
  /// strand them in a subject their parent no longer belongs to.
  Future<void> updateTopic({
    required String topicId,
    required String subjectId,
    required String title,
  }) async {
    final repo = ref.read(topicRepositoryProvider);
    final t = repo.byId(topicId);
    if (t == null) return;

    final moved = t.subjectId != subjectId;
    await repo.upsert(t.copyWith(subjectId: subjectId, title: title));

    if (moved) {
      final subtopicRepo = ref.read(subtopicRepositoryProvider);
      for (final s in subtopicRepo.byTopic(topicId)) {
        final updated = s.copyWith(subjectId: subjectId);
        await subtopicRepo.upsert(updated);
        await _reschedule(updated);
      }
    }
    _backup();
  }

  /// Hard-delete a topic and every subtopic inside it.
  Future<void> deleteTopicCascading(String topicId) async {
    await _deleteTopicInner(topicId);
    _backup();
  }

  /// The delete itself, without the backup — so a cascading subject delete
  /// writes one snapshot at the end rather than one per topic.
  Future<void> _deleteTopicInner(String topicId) async {
    for (final s in ref.read(subtopicRepositoryProvider).byTopic(topicId)) {
      await _deleteSubtopicInner(s.id);
    }
    await ref.read(topicRepositoryProvider).delete(topicId);
  }

  // ----------------------------------------------------------------- subtopic

  Future<Subtopic> createSubtopic({
    required String subjectId,
    required String topicId,
    required String title,
    String? notes,
    Priority priority = Priority.medium,
    Difficulty difficulty = Difficulty.medium,
    int estimatedMinutes = 15,
    List<String> tags = const [],
    int reminderHour = Subtopic.defaultReminderHour,
    int reminderMinute = Subtopic.defaultReminderMinute,
    bool persistentReminders = true,
    List<Attachment> attachments = const [],
    String? presetId,
  }) async {
    // The create form needs an id up front so attachments can be staged into
    // the subtopic's folder before it's saved.
    final id = presetId ?? ref.read(uuidProvider).v4();
    final now = DateTime.now();
    var subtopic = Subtopic(
      id: id,
      subjectId: subjectId,
      topicId: topicId,
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
    final init = ref.read(engineProvider).initialSchedule(subtopic, now: now);
    subtopic = subtopic.copyWith(nextDueAt: init.nextDueAt);
    await ref.read(subtopicRepositoryProvider).upsert(subtopic);
    await _reschedule(subtopic);
    _backup();
    for (final a in attachments.where((a) => a.isLocalFile)) {
      unawaited(BackupService.instance.syncAttachment(id, a.target));
    }
    return subtopic;
  }

  /// Update a subtopic's user-facing fields. Preserves SR state (ease,
  /// repetitions, ladderIndex, lastReviewedAt). If the reminder time changed,
  /// rolls nextDueAt forward to the new hour/minute on the same calendar day
  /// and re-arms the notification.
  Future<void> updateSubtopic({
    required String subtopicId,
    required String subjectId,
    required String topicId,
    required String title,
    String? notes,
    Priority priority = Priority.medium,
    Difficulty difficulty = Difficulty.medium,
    int estimatedMinutes = 15,
    int reminderHour = Subtopic.defaultReminderHour,
    int reminderMinute = Subtopic.defaultReminderMinute,
    bool persistentReminders = true,
    List<Attachment>? attachments,
  }) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;

    final reminderChanged =
        s.reminderHour != reminderHour || s.reminderMinute != reminderMinute;

    var newDue = s.nextDueAt;
    if (reminderChanged) {
      newDue = DateTime(
        s.nextDueAt.year, s.nextDueAt.month, s.nextDueAt.day,
        reminderHour, reminderMinute,
      );
    }

    final updated = s.copyWith(
      subjectId: subjectId,
      topicId: topicId,
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
    await _reschedule(updated);
    _backup();
  }

  Future<void> reviewSubtopic(String subtopicId, ReviewRating rating) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;

    final result = ref.read(engineProvider).schedule(s, rating);
    final updated = s.copyWith(
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
      subtopicId: s.id,
      reviewedAt: DateTime.now(),
      rating: rating,
      intervalAppliedDays: result.nextIntervalDays,
      easeAfter: result.newEase,
    );
    await repo.recordReview(review);
    await _reschedule(updated);
    _backup();
  }

  /// "I revised this today" — the Home checkbox.
  ///
  /// Records a normal `good` review, so the spaced-repetition ladder advances
  /// and the subtopic comes back at the next interval. This is deliberately NOT
  /// the same as [stopRepetition]: ticking a day off should not retire it.
  ///
  /// Returns the number of days until it is next due, so the caller can tell
  /// the user when they'll see it again.
  Future<int> markRevisedToday(String subtopicId) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return 0;
    final result = ref.read(engineProvider).schedule(s, ReviewRating.good);
    await reviewSubtopic(subtopicId, ReviewRating.good);
    return result.nextIntervalDays;
  }

  /// "I didn't get to this."
  ///
  /// Rolls the subtopic to tomorrow at its reminder time and records nothing.
  /// The ladder position, ease and repetition count are all left alone: not
  /// having found time is a scheduling fact, not evidence that the memory
  /// decayed, so it would be wrong to penalise progress for it. A missed day
  /// simply moves.
  Future<int> markNotRevised(String subtopicId) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return 0;

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final due = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      s.reminderHour,
      s.reminderMinute,
    );

    final updated = s.copyWith(nextDueAt: due);
    await repo.upsert(updated);
    await _reschedule(updated);
    _backup();
    return 1;
  }

  /// Retire a subtopic the user has mastered: no further reminders, ever.
  ///
  /// Distinct from pausing — pause is a temporary hold, this is "I know this
  /// now". It stays visible inside its topic so the history isn't lost, and
  /// [resumeRepetition] puts it back in rotation.
  Future<void> stopRepetition(String subtopicId) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;
    await repo.upsert(s.copyWith(status: SubtopicStatus.completed));
    await NotificationService.instance.cancelForSubtopic(subtopicId);
    _backup();
  }

  /// Put a stopped (or paused) subtopic back into the schedule, due today at
  /// its reminder time.
  Future<void> resumeRepetition(String subtopicId) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;
    final now = DateTime.now();
    var due = DateTime(
      now.year,
      now.month,
      now.day,
      s.reminderHour,
      s.reminderMinute,
    );
    if (!due.isAfter(now)) due = due.add(const Duration(days: 1));

    final updated =
        s.copyWith(status: SubtopicStatus.active, nextDueAt: due);
    await repo.upsert(updated);
    await _reschedule(updated);
    _backup();
  }

  /// Wipe every subject, topic, subtopic, review and attachment file.
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

    for (final s in ref.read(subtopicRepositoryProvider).all()) {
      await AttachmentService.instance.deleteAllFor(s.id);
    }
    // The folder's copies too. Clearing only local files left every attached
    // video and document sitting in the user's folder after a reset.
    await BackupService.instance.clearFolderFiles();

    final store = StorageService.instance;
    await store.subtopics.deleteAll(store.subtopics.keys.toList());
    await store.topics.deleteAll(store.topics.keys.toList());
    await store.subjects.deleteAll(store.subjects.keys.toList());
    await store.reviews.deleteAll(store.reviews.keys.toList());

    await BackupService.instance.flush();
  }

  /// Replace a subtopic's attachment list (add or remove from the detail page).
  Future<void> setAttachments(
    String subtopicId,
    List<Attachment> attachments,
  ) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;

    final before = {for (final a in s.attachments) a.id: a};
    final after = {for (final a in attachments) a.id: a};

    await repo.upsert(s.copyWith(attachments: attachments));
    _backup();

    // Copy each new file across once, and drop removed ones. Attachments are
    // immutable, so this is the only time their bytes ever move — the folder
    // copy is never rebuilt wholesale.
    for (final a in after.values) {
      if (before.containsKey(a.id) || !a.isLocalFile) continue;
      unawaited(BackupService.instance.syncAttachment(subtopicId, a.target));
    }
    for (final a in before.values) {
      if (after.containsKey(a.id) || !a.isLocalFile) continue;
      unawaited(
        BackupService.instance.removeAttachmentFromFolder(subtopicId, a.target),
      );
    }
  }

  Future<void> snoozeSubtopic(String subtopicId, Duration by) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;
    final updated = s.copyWith(nextDueAt: DateTime.now().add(by));
    await repo.upsert(updated);
    await _reschedule(updated);
    _backup();
  }

  Future<void> setStatus(String subtopicId, SubtopicStatus status) async {
    final repo = ref.read(subtopicRepositoryProvider);
    final s = repo.byId(subtopicId);
    if (s == null) return;
    final updated = s.copyWith(status: status);
    await repo.upsert(updated);
    if (status == SubtopicStatus.active) {
      await _reschedule(updated);
    } else {
      await NotificationService.instance.cancelForSubtopic(subtopicId);
    }
    _backup();
  }

  /// Hard-delete a subtopic and its review history.
  ///
  /// Order matters: the Hive delete happens FIRST. It used to sit behind an
  /// `await` on the notification cancel, so when the notification plugin threw
  /// (see the exact-alarm bug in [NotificationService]) the delete never ran
  /// and the record appeared undeletable.
  Future<void> deleteSubtopic(String subtopicId) async {
    await _deleteSubtopicInner(subtopicId);
    _backup();
  }

  Future<void> _deleteSubtopicInner(String subtopicId) async {
    final repo = ref.read(subtopicRepositoryProvider);
    await repo.delete(subtopicId);
    await repo.deleteReviewsForSubtopic(subtopicId);
    // Attached files live outside Hive, so they'd otherwise sit on disk
    // forever after the record that referenced them is gone.
    await AttachmentService.instance.deleteAllFor(subtopicId);
    unawaited(BackupService.instance.removeSubtopicFilesFromFolder(subtopicId));
    await NotificationService.instance.cancelForSubtopic(subtopicId);
  }
}

final topicCommandsProvider = Provider<TopicCommands>((ref) => TopicCommands(ref));
