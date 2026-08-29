import 'package:hive/hive.dart';
import '../../domain/entities/attachment.dart';
import '../../domain/entities/topic.dart';

part 'topic_model.g.dart';

@HiveType(typeId: 2)
class TopicModel extends HiveObject {
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
  @HiveField(15) int statusIndex;        // TopicStatus.index
  @HiveField(16) int reminderHour;
  @HiveField(17) int reminderMinute;
  @HiveField(18) bool persistentReminders;
  /// JSON-encoded [Attachment]s. A List<String> needs no Hive adapter,
  /// so this was added without registering a new typeId.
  @HiveField(19) List<String> attachments;

  TopicModel({
    required this.id,
    required this.subjectId,
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
    this.reminderHour = 19,
    this.reminderMinute = 0,
    this.persistentReminders = true,
    this.attachments = const [],
  });

  factory TopicModel.fromEntity(Topic t) => TopicModel(
        id: t.id,
        subjectId: t.subjectId,
        title: t.title,
        notes: t.notes,
        tags: List<String>.from(t.tags),
        priorityIndex: t.priority.index,
        difficultyIndex: t.difficulty.index,
        estimatedMinutes: t.estimatedMinutes,
        createdAt: t.createdAt,
        repetitions: t.repetitions,
        ease: t.ease,
        currentIntervalDays: t.currentIntervalDays,
        ladderIndex: t.ladderIndex,
        nextDueAt: t.nextDueAt,
        lastReviewedAt: t.lastReviewedAt,
        statusIndex: t.status.index,
        reminderHour: t.reminderHour,
        reminderMinute: t.reminderMinute,
        persistentReminders: t.persistentReminders,
        attachments: Attachment.encodeAll(t.attachments),
      );

  Topic toEntity() => Topic(
        id: id,
        subjectId: subjectId,
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
        status: TopicStatus.values[statusIndex],
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        persistentReminders: persistentReminders,
        attachments: Attachment.decodeAll(attachments),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'subjectId': subjectId, 'title': title, 'notes': notes,
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

  factory TopicModel.fromJson(Map<String, dynamic> j) => TopicModel(
        id: j['id'] as String,
        subjectId: j['subjectId'] as String,
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
        reminderHour: (j['reminderHour'] as int?) ?? 19,
        reminderMinute: (j['reminderMinute'] as int?) ?? 0,
        persistentReminders: (j['persistentReminders'] as bool?) ?? true,
        attachments:
            (j['attachments'] as List?)?.cast<String>() ?? const [],
      );
}
