import 'package:hive/hive.dart';
import '../../domain/entities/topic.dart';

part 'topic_model.g.dart';

/// Hive-persisted view of [Topic], the grouping layer added with subtopics.
///
/// typeId 4 is a fresh number, and `StorageService.topicsBox` is a fresh box,
/// so nothing on disk had to be rewritten to introduce it. typeId 2 continues
/// to mean what it always did — the scheduled leaf, now called a subtopic.
/// typeIds are permanent: never reuse or renumber one after the app ships.
@HiveType(typeId: 4)
class TopicModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String subjectId;
  @HiveField(2) String title;
  @HiveField(3) DateTime createdAt;

  TopicModel({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.createdAt,
  });

  factory TopicModel.fromEntity(Topic t) => TopicModel(
        id: t.id,
        subjectId: t.subjectId,
        title: t.title,
        createdAt: t.createdAt,
      );

  Topic toEntity() => Topic(
        id: id,
        subjectId: subjectId,
        title: title,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TopicModel.fromJson(Map<String, dynamic> j) => TopicModel(
        id: j['id'] as String,
        subjectId: j['subjectId'] as String,
        title: j['title'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
