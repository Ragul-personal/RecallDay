import 'package:hive/hive.dart';
import '../../domain/entities/subject.dart';

part 'subject_model.g.dart';

/// Hive-persisted view of [Subject]. typeId is permanent — never reuse or
/// renumber after the app ships, or you will corrupt user databases.
@HiveType(typeId: 1)
class SubjectModel extends HiveObject {
  @HiveField(0) String id;
  @HiveField(1) String name;
  @HiveField(2) int colorValue;
  @HiveField(3) String iconKey;
  @HiveField(4) DateTime createdAt;
  @HiveField(5) bool archived;

  SubjectModel({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.createdAt,
    this.archived = false,
  });

  factory SubjectModel.fromEntity(Subject s) => SubjectModel(
        id: s.id,
        name: s.name,
        colorValue: s.colorValue,
        iconKey: s.iconKey,
        createdAt: s.createdAt,
        archived: s.archived,
      );

  Subject toEntity() => Subject(
        id: id,
        name: name,
        colorValue: colorValue,
        iconKey: iconKey,
        createdAt: createdAt,
        archived: archived,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
        'createdAt': createdAt.toIso8601String(),
        'archived': archived,
      };

  factory SubjectModel.fromJson(Map<String, dynamic> j) => SubjectModel(
        id: j['id'] as String,
        name: j['name'] as String,
        colorValue: j['colorValue'] as int,
        iconKey: j['iconKey'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        archived: (j['archived'] as bool?) ?? false,
      );
}
