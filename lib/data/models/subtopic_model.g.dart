// GENERATED — checked in so the project compiles before `build_runner build`.
// ignore_for_file: type=lint

part of 'subtopic_model.dart';

class SubtopicModelAdapter extends TypeAdapter<SubtopicModel> {
  @override
  final int typeId = 2;

  @override
  SubtopicModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SubtopicModel(
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
      // Not Subtopic.defaultReminderHour: a record written without this field
      // was scheduled under the old 7pm default, and reading it back as 6am
      // would move a reminder the user never asked to move.
      reminderHour: (fields[16] as int?) ?? SubtopicModel._legacyReminderHour,
      reminderMinute: (fields[17] as int?) ?? 0,
      persistentReminders: (fields[18] as bool?) ?? true,
      // Field 19 is absent in boxes written by earlier builds, so a null
      // here is the normal case for existing records, not an error.
      attachments: (fields[19] as List?)?.cast<String>() ?? const [],
      // Field 20 likewise: everything written by an earlier build predates
      // the topic layer. The migration fills these in on first launch.
      topicId: (fields[20] as String?) ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, SubtopicModel obj) {
    writer
      ..writeByte(21)
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
      ..writeByte(18)..write(obj.persistentReminders)
      ..writeByte(19)..write(obj.attachments)
      ..writeByte(20)..write(obj.topicId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubtopicModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
