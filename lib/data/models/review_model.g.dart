// GENERATED — checked in so the project compiles before `build_runner build`.
// ignore_for_file: type=lint

part of 'review_model.dart';

class ReviewModelAdapter extends TypeAdapter<ReviewModel> {
  @override
  final int typeId = 3;

  @override
  ReviewModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReviewModel(
      id: fields[0] as String,
      subtopicId: fields[1] as String,
      reviewedAt: fields[2] as DateTime,
      ratingIndex: fields[3] as int,
      intervalAppliedDays: fields[4] as int,
      easeAfter: (fields[5] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, ReviewModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.subtopicId)
      ..writeByte(2)..write(obj.reviewedAt)
      ..writeByte(3)..write(obj.ratingIndex)
      ..writeByte(4)..write(obj.intervalAppliedDays)
      ..writeByte(5)..write(obj.easeAfter);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
