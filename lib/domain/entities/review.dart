import 'package:equatable/equatable.dart';
import 'topic.dart';

/// Immutable record of one review event. Used for analytics + Firestore sync.
class Review extends Equatable {
  final String id;
  final String topicId;
  final DateTime reviewedAt;
  final ReviewRating rating;
  final int intervalAppliedDays;
  final double easeAfter;

  const Review({
    required this.id,
    required this.topicId,
    required this.reviewedAt,
    required this.rating,
    required this.intervalAppliedDays,
    required this.easeAfter,
  });

  @override
  List<Object?> get props =>
      [id, topicId, reviewedAt, rating, intervalAppliedDays, easeAfter];
}
