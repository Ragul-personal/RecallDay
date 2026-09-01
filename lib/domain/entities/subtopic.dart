import 'package:equatable/equatable.dart';

import 'attachment.dart';

/// User self-rating after a review session. Drives the ease update; only
/// `forgot` and `easy` change the schedule itself (see [SpacedRepetitionEngine]).
enum ReviewRating {
  forgot,   // failed recall — rewind to the first rung, decrease ease
  hard,     // recalled with difficulty — lower ease, same rung as good
  good,     // standard — advance one rung
  easy,     // very confident — skip a rung, raise ease
}

enum SubtopicStatus {
  active,
  paused,
  completed,
}

enum Difficulty { easy, medium, hard }
enum Priority { low, medium, high }

/// The leaf of the library: Subject → Topic → **Subtopic**.
///
/// A subtopic is the only thing the app actually schedules. Subjects and
/// topics are grouping layers with no spaced-repetition state of their own,
/// which is why every reminder, review record and attachment hangs off an id
/// from here.
///
/// SR state lives on the subtopic. The scheduler walks a fixed interval ladder
/// (default Leitner: 1d, 3d, 7d, 14d, 30d) and then holds on the last rung, so
/// revisions settle at one a month rather than growing without bound.
///   • [ladderIndex] is the current rung; it never exceeds the ladder's length.
///   • A "forgot" rating at any stage resets repetitions to 0 and rewinds to
///     the first ladder rung, but preserves an attenuated ease factor.
///   • [ease] and [currentIntervalDays] are still recorded on every review;
///     ease no longer feeds the interval.
///
/// [subjectId] is denormalised alongside [topicId] on purpose: the Today
/// screen, the calendar and the notification body all want the subject's name
/// and colour, and carrying it here means none of them has to walk up through
/// the topic box to find it. `TopicCommands` keeps the two in step — moving a
/// topic to another subject rewrites its subtopics' [subjectId] too.
class Subtopic extends Equatable {
  final String id;
  final String subjectId;
  final String topicId;
  final String title;
  final String? notes;          // markdown
  final List<String> tags;
  final Priority priority;
  final Difficulty difficulty;
  final int estimatedMinutes;
  final DateTime createdAt;

  // Spaced repetition state ----------------------------------------------------
  final int repetitions;           // count of successful (>=hard) reviews
  final double ease;               // SM-2 ease factor; clamped [1.3, 3.0]
  final int currentIntervalDays;   // last applied interval in days
  final int ladderIndex;           // index into the fixed-interval ladder
  final DateTime nextDueAt;        // next reminder timestamp
  final DateTime? lastReviewedAt;
  final SubtopicStatus status;

  // Reminder configuration -----------------------------------------------------
  final int reminderHour;          // local hour-of-day, 0..23
  final int reminderMinute;        // 0..59
  final bool persistentReminders;  // re-fire daily until reviewed

  /// Files, images, videos and links saved against this subtopic.
  final List<Attachment> attachments;

  /// The default reminder hour for anything created from now on.
  ///
  /// Was 19:00. Revision lands better first thing, and an evening reminder
  /// arrived after the day was already spent. Existing subtopics keep whatever
  /// hour they were saved with — see the deserialisation fallbacks in
  /// `SubtopicModel`, which still default to 19 for records written before
  /// this field existed.
  static const int defaultReminderHour = 6;
  static const int defaultReminderMinute = 0;

  const Subtopic({
    required this.id,
    required this.subjectId,
    required this.topicId,
    required this.title,
    this.notes,
    this.tags = const [],
    this.priority = Priority.medium,
    this.difficulty = Difficulty.medium,
    this.estimatedMinutes = 15,
    required this.createdAt,
    this.repetitions = 0,
    this.ease = 2.5,
    this.currentIntervalDays = 0,
    this.ladderIndex = 0,
    required this.nextDueAt,
    this.lastReviewedAt,
    this.status = SubtopicStatus.active,
    this.reminderHour = defaultReminderHour,
    this.reminderMinute = defaultReminderMinute,
    this.persistentReminders = true,
    this.attachments = const [],
  });

  /// True from midnight of the day it falls due — NOT from its reminder time.
  ///
  /// The day is the unit this app schedules in; the reminder hour only decides
  /// when the phone buzzes. Testing `nextDueAt <= now` meant a subtopic due at
  /// 6am was listed on the Today screen from 00:00 but its Revise button
  /// stayed hidden until 6am, which reads as a bug rather than a policy.
  bool get isDue =>
      status == SubtopicStatus.active && !nextDueAt.isAfter(_endOfToday());

  /// Due on an earlier calendar day than today.
  ///
  /// Also day-granular, for the same reason: with an hour-based test a
  /// subtopic missed yesterday only became "overdue" once today's clock passed
  /// its reminder hour, so between midnight and 6am it sat in "Due today"
  /// beside work that genuinely belonged to today.
  bool get isOverdue =>
      status == SubtopicStatus.active && nextDueAt.isBefore(_startOfToday());

  static DateTime _startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _endOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
  }

  Subtopic copyWith({
    String? subjectId,
    String? topicId,
    String? title,
    String? notes,
    List<String>? tags,
    Priority? priority,
    Difficulty? difficulty,
    int? estimatedMinutes,
    int? repetitions,
    double? ease,
    int? currentIntervalDays,
    int? ladderIndex,
    DateTime? nextDueAt,
    DateTime? lastReviewedAt,
    SubtopicStatus? status,
    int? reminderHour,
    int? reminderMinute,
    bool? persistentReminders,
    List<Attachment>? attachments,
  }) {
    return Subtopic(
      id: id,
      subjectId: subjectId ?? this.subjectId,
      topicId: topicId ?? this.topicId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      priority: priority ?? this.priority,
      difficulty: difficulty ?? this.difficulty,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      createdAt: createdAt,
      repetitions: repetitions ?? this.repetitions,
      ease: ease ?? this.ease,
      currentIntervalDays: currentIntervalDays ?? this.currentIntervalDays,
      ladderIndex: ladderIndex ?? this.ladderIndex,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      status: status ?? this.status,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      persistentReminders: persistentReminders ?? this.persistentReminders,
      attachments: attachments ?? this.attachments,
    );
  }

  @override
  List<Object?> get props => [
        id, subjectId, topicId, title, notes, tags, priority, difficulty,
        estimatedMinutes, createdAt, repetitions, ease, currentIntervalDays,
        ladderIndex, nextDueAt, lastReviewedAt, status, reminderHour,
        reminderMinute, persistentReminders, attachments,
      ];
}
