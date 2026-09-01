import 'package:hive/hive.dart';
import '../../domain/entities/review.dart';
import '../../domain/entities/subtopic.dart';

part 'review_model.g.dart';

/// Hive-persisted view of [Review].
///
/// Field 1 and the JSON key are still `topicId`, and must stay that way: every
/// review ever recorded is keyed by it, and the id it holds is the leaf's id,
/// which the subtopic layer did not change. Only the Dart identifier moved.
@HiveType(typeId: 3)
class ReviewModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String subtopicId;
  @HiveField(2) DateTime reviewedAt;
  @HiveField(3) int ratingIndex;
  @HiveField(4) int intervalAppliedDays;
  @HiveField(5) double easeAfter;

  ReviewModel({
    required this.id,
    required this.subtopicId,
    required this.reviewedAt,
    required this.ratingIndex,
    required this.intervalAppliedDays,
    required this.easeAfter,
  });

  factory ReviewModel.fromEntity(Review r) => ReviewModel(
        id: r.id,
        subtopicId: r.subtopicId,
        reviewedAt: r.reviewedAt,
        ratingIndex: r.rating.index,
        intervalAppliedDays: r.intervalAppliedDays,
        easeAfter: r.easeAfter,
      );

  Review toEntity() => Review(
        id: id,
        subtopicId: subtopicId,
        reviewedAt: reviewedAt,
        rating: ReviewRating.values[ratingIndex],
        intervalAppliedDays: intervalAppliedDays,
        easeAfter: easeAfter,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': subtopicId,
        'reviewedAt': reviewedAt.toIso8601String(),
        'ratingIndex': ratingIndex,
        'intervalAppliedDays': intervalAppliedDays,
        'easeAfter': easeAfter,
      };

  factory ReviewModel.fromJson(Map<String, dynamic> j) => ReviewModel(
        id: j['id'] as String,
        subtopicId: (j['subtopicId'] as String?) ?? j['topicId'] as String,
        reviewedAt: DateTime.parse(j['reviewedAt'] as String),
        ratingIndex: (j['ratingIndex'] as int?) ?? ReviewRating.good.index,
        intervalAppliedDays: (j['intervalAppliedDays'] as int?) ?? 0,
        easeAfter: (j['easeAfter'] as num?)?.toDouble() ?? 2.5,
      );
}
