import 'package:hive/hive.dart';
import '../../domain/entities/review.dart';
import '../../domain/entities/topic.dart';

part 'review_model.g.dart';

@HiveType(typeId: 3)
class ReviewModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String topicId;
  @HiveField(2) DateTime reviewedAt;
  @HiveField(3) int ratingIndex;
  @HiveField(4) int intervalAppliedDays;
  @HiveField(5) double easeAfter;

  ReviewModel({
    required this.id,
    required this.topicId,
    required this.reviewedAt,
    required this.ratingIndex,
    required this.intervalAppliedDays,
    required this.easeAfter,
  });

  factory ReviewModel.fromEntity(Review r) => ReviewModel(
        id: r.id,
        topicId: r.topicId,
        reviewedAt: r.reviewedAt,
        ratingIndex: r.rating.index,
        intervalAppliedDays: r.intervalAppliedDays,
        easeAfter: r.easeAfter,
      );

  Review toEntity() => Review(
        id: id,
        topicId: topicId,
        reviewedAt: reviewedAt,
        rating: ReviewRating.values[ratingIndex],
        intervalAppliedDays: intervalAppliedDays,
        easeAfter: easeAfter,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topicId': topicId,
        'reviewedAt': reviewedAt.toIso8601String(),
        'ratingIndex': ratingIndex,
        'intervalAppliedDays': intervalAppliedDays,
        'easeAfter': easeAfter,
      };

  factory ReviewModel.fromJson(Map<String, dynamic> j) => ReviewModel(
        id: j['id'] as String,
        topicId: j['topicId'] as String,
        reviewedAt: DateTime.parse(j['reviewedAt'] as String),
        ratingIndex: (j['ratingIndex'] as int?) ?? ReviewRating.good.index,
        intervalAppliedDays: (j['intervalAppliedDays'] as int?) ?? 0,
        easeAfter: (j['easeAfter'] as num?)?.toDouble() ?? 2.5,
      );
}
