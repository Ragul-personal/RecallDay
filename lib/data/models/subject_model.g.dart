// GENERATED — checked in so the project compiles before `build_runner build`.
// If you change SubjectModel fields, run:
//     dart run build_runner build --delete-conflicting-outputs
// and let the generator overwrite this file.
// ignore_for_file: type=lint

part of 'subject_model.dart';

class SubjectModelAdapter extends TypeAdapter<SubjectModel> {
  @override
  final int typeId = 1;

  @override
  SubjectModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SubjectModel(
      id: fields[0] as String,
      name: fields[1] as String,
      colorValue: fields[2] as int,
      iconKey: fields[3] as String,
      createdAt: fields[4] as DateTime,
      archived: (fields[5] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, SubjectModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.colorValue)
      ..writeByte(3)..write(obj.iconKey)
      ..writeByte(4)..write(obj.createdAt)
      ..writeByte(5)..write(obj.archived);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubjectModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
