// GENERATED — checked in so the project compiles before `build_runner build`.
// ignore_for_file: type=lint

part of 'topic_model.dart';

class TopicModelAdapter extends TypeAdapter<TopicModel> {
  @override
  final int typeId = 2;

  @override
  TopicModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TopicModel(
      id: fields[0] as String,
      subjectId: fields[1] as String,
      title: fields[2] as String,
      notes: fields[3] as String?,
      tags: (fields[4] as List?)?.cast<String>() ?? const [],
      priorityIndex: (fields[5] as int?) ?? 1,
      difficultyIndex: (fields[6] as int?) ?? 1,
      estimatedMinutes: (fields[7] as int?) ?? 15,
      createdAt: fields[8] as DateTime,
      repetitions: (fields[9] as int?) ?? 0,
      ease: (fields[10] as num?)?.toDouble() ?? 2.5,
      currentIntervalDays: (fields[11] as int?) ?? 0,
      ladderIndex: (fields[12] as int?) ?? 0,
      nextDueAt: fields[13] as DateTime,
      lastReviewedAt: fields[14] as DateTime?,
      statusIndex: (fields[15] as int?) ?? 0,
      reminderHour: (fields[16] as int?) ?? 19,
      reminderMinute: (fields[17] as int?) ?? 0,
      persistentReminders: (fields[18] as bool?) ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, TopicModel obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.subjectId)
      ..writeByte(2)..write(obj.title)
      ..writeByte(3)..write(obj.notes)
      ..writeByte(4)..write(obj.tags)
      ..writeByte(5)..write(obj.priorityIndex)
      ..writeByte(6)..write(obj.difficultyIndex)
      ..writeByte(7)..write(obj.estimatedMinutes)
      ..writeByte(8)..write(obj.createdAt)
      ..writeByte(9)..write(obj.repetitions)
      ..writeByte(10)..write(obj.ease)
      ..writeByte(11)..write(obj.currentIntervalDays)
      ..writeByte(12)..write(obj.ladderIndex)
      ..writeByte(13)..write(obj.nextDueAt)
      ..writeByte(14)..write(obj.lastReviewedAt)
      ..writeByte(15)..write(obj.statusIndex)
      ..writeByte(16)..write(obj.reminderHour)
      ..writeByte(17)..write(obj.reminderMinute)
      ..writeByte(18)..write(obj.persistentReminders);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
