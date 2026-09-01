import 'package:hive/hive.dart';
import '../../domain/entities/attachment.dart';
import '../../domain/entities/subtopic.dart';

part 'subtopic_model.g.dart';

/// Hive-persisted view of [Subtopic].
///
/// **typeId 2 is deliberate.** These are the same records the app has written
/// since 1.0.0, when the leaf of the tree was called a "topic". Nothing about
/// them moved when the subtopic layer landed: same box, same typeId, same ids,
/// same field numbers. The only addition is field 20, [topicId], which is
/// absent in every record written before the topic layer existed and is
/// filled in by `runHierarchyMigration` on first launch.
///
/// Renumbering the typeId, or renaming the box, would orphan every existing
/// database. Don't.
@HiveType(typeId: 2)
class SubtopicModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String subjectId;
  @HiveField(2) String title;
  @HiveField(3) String? notes;
  @HiveField(4) List<String> tags;
  @HiveField(5) int priorityIndex;       // Priority.index
  @HiveField(6) int difficultyIndex;     // Difficulty.index
  @HiveField(7) int estimatedMinutes;
  @HiveField(8) DateTime createdAt;
  @HiveField(9) int repetitions;
  @HiveField(10) double ease;
  @HiveField(11) int currentIntervalDays;
  @HiveField(12) int ladderIndex;
  @HiveField(13) DateTime nextDueAt;
  @HiveField(14) DateTime? lastReviewedAt;
  @HiveField(15) int statusIndex;        // SubtopicStatus.index
  @HiveField(16) int reminderHour;
  @HiveField(17) int reminderMinute;
  @HiveField(18) bool persistentReminders;
  /// JSON-encoded [Attachment]s. A List<String> needs no Hive adapter,
  /// so this was added without registering a new typeId.
  @HiveField(19) List<String> attachments;
  /// Parent topic. Empty on records written by an earlier build; the migration
  /// gives each of those a topic of its own rather than leaving it unfiled.
  @HiveField(20) String topicId;

  SubtopicModel({
    required this.id,
    required this.subjectId,
    this.topicId = '',
    required this.title,
    this.notes,
    this.tags = const [],
    this.priorityIndex = 1,
    this.difficultyIndex = 1,
    this.estimatedMinutes = 15,
    required this.createdAt,
    this.repetitions = 0,
    this.ease = 2.5,
    this.currentIntervalDays = 0,
    this.ladderIndex = 0,
    required this.nextDueAt,
    this.lastReviewedAt,
    this.statusIndex = 0,
    this.reminderHour = Subtopic.defaultReminderHour,
    this.reminderMinute = Subtopic.defaultReminderMinute,
    this.persistentReminders = true,
    this.attachments = const [],
  });

  /// The reminder hour to assume for a record saved before the field existed.
  ///
  /// NOT [Subtopic.defaultReminderHour]. That constant is the default for
  /// things created from now on; this one reconstructs what an old record was
  /// actually scheduled at, and changing it would silently move every
  /// pre-existing reminder.
  static const int _legacyReminderHour = 19;

  factory SubtopicModel.fromEntity(Subtopic s) => SubtopicModel(
        id: s.id,
        subjectId: s.subjectId,
        topicId: s.topicId,
        title: s.title,
        notes: s.notes,
        tags: List<String>.from(s.tags),
        priorityIndex: s.priority.index,
        difficultyIndex: s.difficulty.index,
        estimatedMinutes: s.estimatedMinutes,
        createdAt: s.createdAt,
        repetitions: s.repetitions,
        ease: s.ease,
        currentIntervalDays: s.currentIntervalDays,
        ladderIndex: s.ladderIndex,
        nextDueAt: s.nextDueAt,
        lastReviewedAt: s.lastReviewedAt,
        statusIndex: s.status.index,
        reminderHour: s.reminderHour,
        reminderMinute: s.reminderMinute,
        persistentReminders: s.persistentReminders,
        attachments: Attachment.encodeAll(s.attachments),
      );

  Subtopic toEntity() => Subtopic(
        id: id,
        subjectId: subjectId,
        topicId: topicId,
        title: title,
        notes: notes,
        tags: List<String>.from(tags),
        priority: Priority.values[priorityIndex],
        difficulty: Difficulty.values[difficultyIndex],
        estimatedMinutes: estimatedMinutes,
        createdAt: createdAt,
        repetitions: repetitions,
        ease: ease,
        currentIntervalDays: currentIntervalDays,
        ladderIndex: ladderIndex,
        nextDueAt: nextDueAt,
        lastReviewedAt: lastReviewedAt,
        status: SubtopicStatus.values[statusIndex],
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        persistentReminders: persistentReminders,
        attachments: Attachment.decodeAll(attachments),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'subjectId': subjectId, 'topicId': topicId,
        'title': title, 'notes': notes,
        'tags': tags, 'priorityIndex': priorityIndex,
        'difficultyIndex': difficultyIndex, 'estimatedMinutes': estimatedMinutes,
        'createdAt': createdAt.toIso8601String(),
        'repetitions': repetitions, 'ease': ease,
        'currentIntervalDays': currentIntervalDays, 'ladderIndex': ladderIndex,
        'nextDueAt': nextDueAt.toIso8601String(),
        'lastReviewedAt': lastReviewedAt?.toIso8601String(),
        'statusIndex': statusIndex,
        'reminderHour': reminderHour, 'reminderMinute': reminderMinute,
        'persistentReminders': persistentReminders,
        'attachments': attachments,
      };

  /// Reads both shapes: a subtopic, and the older "topic" record it grew
  /// from — the same object without `topicId`.
  factory SubtopicModel.fromJson(Map<String, dynamic> j) => SubtopicModel(
        id: j['id'] as String,
        subjectId: j['subjectId'] as String,
        topicId: (j['topicId'] as String?) ?? '',
        title: j['title'] as String,
        notes: j['notes'] as String?,
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
        priorityIndex: (j['priorityIndex'] as int?) ?? 1,
        difficultyIndex: (j['difficultyIndex'] as int?) ?? 1,
        estimatedMinutes: (j['estimatedMinutes'] as int?) ?? 15,
        createdAt: DateTime.parse(j['createdAt'] as String),
        repetitions: (j['repetitions'] as int?) ?? 0,
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
        currentIntervalDays: (j['currentIntervalDays'] as int?) ?? 0,
        ladderIndex: (j['ladderIndex'] as int?) ?? 0,
        nextDueAt: DateTime.parse(j['nextDueAt'] as String),
        lastReviewedAt: j['lastReviewedAt'] == null
            ? null
            : DateTime.parse(j['lastReviewedAt'] as String),
        statusIndex: (j['statusIndex'] as int?) ?? 0,
        reminderHour: (j['reminderHour'] as int?) ?? _legacyReminderHour,
        reminderMinute: (j['reminderMinute'] as int?) ?? 0,
        persistentReminders: (j['persistentReminders'] as bool?) ?? true,
        attachments:
            (j['attachments'] as List?)?.cast<String>() ?? const [],
      );
}
