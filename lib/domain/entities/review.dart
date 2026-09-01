import 'package:equatable/equatable.dart';
import 'subtopic.dart';

/// Immutable record of one review event. Drives the streak and the calendar's
/// view of the past.
///
/// [subtopicId] is the field that was called `topicId` before the subtopic
/// layer existed. The id itself never changed — the records the old build
/// wrote still point at exactly the right row — so the Hive field index and
/// the JSON key both keep their historical name; only the Dart identifier
/// moved. See `ReviewModel`.
class Review extends Equatable {
  final String id;
  final String subtopicId;
  final DateTime reviewedAt;
  final ReviewRating rating;
  final int intervalAppliedDays;
  final double easeAfter;

  const Review({
    required this.id,
    required this.subtopicId,
    required this.reviewedAt,
    required this.rating,
    required this.intervalAppliedDays,
    required this.easeAfter,
  });

  @override
  List<Object?> get props =>
      [id, subtopicId, reviewedAt, rating, intervalAppliedDays, easeAfter];
}
