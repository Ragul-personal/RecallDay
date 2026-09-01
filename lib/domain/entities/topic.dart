import 'package:equatable/equatable.dart';

/// The middle layer of the library: Subject → **Topic** → Subtopic.
///
/// A topic is a grouping only. It carries no schedule, no reminder time and no
/// review history — all of that belongs to the [Subtopic]s underneath it, which
/// is what keeps "how do I revise this?" a question with exactly one answer per
/// row on the Today screen.
///
/// A topic *was* the scheduled thing before subtopics existed. Those records
/// are still in every user's database, so the upgrade does not move them: they
/// stay leaves (now called subtopics) and each is handed a topic of the same
/// name to live under. See `runHierarchyMigration`.
class Topic extends Equatable {
  final String id;
  final String subjectId;
  final String title;
  final DateTime createdAt;

  const Topic({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.createdAt,
  });

  Topic copyWith({
    String? subjectId,
    String? title,
  }) {
    return Topic(
      id: id,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id, subjectId, title, createdAt];
}
