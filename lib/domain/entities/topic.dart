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

enum TopicStatus {
  active,
  paused,
  completed,
}

enum Difficulty { easy, medium, hard }
enum Priority { low, medium, high }

/// SR state lives on the Topic. The scheduler walks a fixed interval ladder
/// (default Leitner: 1d, 3d, 7d, 14d, 30d) and then holds on the last rung, so
/// revisions settle at one a month rather than growing without bound.
///   • [ladderIndex] is the current rung; it never exceeds the ladder's length.
///   • A "forgot" rating at any stage resets repetitions to 0 and rewinds to
///     the first ladder rung, but preserves an attenuated ease factor.
///   • [ease] and [currentIntervalDays] are still recorded on every review;
///     ease no longer feeds the interval.
class Topic extends Equatable {
  final String id;
  final String subjectId;
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
  final TopicStatus status;

  // Reminder configuration -----------------------------------------------------
  final int reminderHour;          // local hour-of-day, 0..23
  final int reminderMinute;        // 0..59
  final bool persistentReminders;  // re-fire daily until reviewed

  /// Files, images, videos and links saved against this topic.
  final List<Attachment> attachments;

  const Topic({
    required this.id,
    required this.subjectId,
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
    this.status = TopicStatus.active,
    this.reminderHour = 19,
    this.reminderMinute = 0,
    this.persistentReminders = true,
    this.attachments = const [],
  });

  bool get isDue =>
      status == TopicStatus.active && !nextDueAt.isAfter(DateTime.now());

  bool get isOverdue =>
      status == TopicStatus.active &&
      nextDueAt.isBefore(DateTime.now().subtract(const Duration(hours: 24)));

  Topic copyWith({
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
    TopicStatus? status,
    int? reminderHour,
    int? reminderMinute,
    bool? persistentReminders,
    List<Attachment>? attachments,
  }) {
    return Topic(
      id: id,
      subjectId: subjectId,
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
        id, subjectId, title, notes, tags, priority, difficulty,
        estimatedMinutes, createdAt, repetitions, ease, currentIntervalDays,
        ladderIndex, nextDueAt, lastReviewedAt, status, reminderHour,
        reminderMinute, persistentReminders, attachments,
      ];
}
