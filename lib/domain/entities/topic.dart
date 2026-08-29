import 'package:equatable/equatable.dart';

/// User self-rating after a review session. Drives the SM-2-derived ease update.
enum ReviewRating {
  forgot,   // failed recall — restart interval, decrease ease
  hard,     // recalled with difficulty — small interval growth, lower ease
  good,     // standard — multiply by ease factor
  easy,     // very confident — multiply by ease factor * easyBonus
}

enum TopicStatus {
  active,
  paused,
  completed,
}

enum Difficulty { easy, medium, hard }
enum Priority { low, medium, high }

/// SR state lives on the Topic. We use a hybrid scheduler:
///   • While `repetitions == 0`, we use the user-configured fixed interval
///     ladder (default Leitner: 1d, 3d, 7d, 15d, 30d, 60d, 90d).
///   • Once `repetitions >= 2`, we switch to SM-2: next = lastInterval * ease.
///   • A "forgot" rating at any stage resets repetitions to 0 and rewinds to
///     the first ladder rung, but preserves an attenuated ease factor.
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
    );
  }

  @override
  List<Object?> get props => [
        id, subjectId, title, notes, tags, priority, difficulty,
        estimatedMinutes, createdAt, repetitions, ease, currentIntervalDays,
        ladderIndex, nextDueAt, lastReviewedAt, status, reminderHour,
        reminderMinute, persistentReminders,
      ];
}
