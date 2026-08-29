import 'dart:async';
import '../../domain/entities/subject.dart';
import '../../domain/repositories/subject_repository.dart';
import '../models/subject_model.dart';
import '../../services/storage_service.dart';

class SubjectRepositoryImpl implements SubjectRepository {
  final _store = StorageService.instance;

  @override
  List<Subject> all() => _store.subjects.values
      .where((m) => !m.archived)
      .map((m) => m.toEntity())
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Subject? byId(String id) => _store.subjects.get(id)?.toEntity();

  @override
  Future<void> upsert(Subject s) async {
    await _store.subjects.put(s.id, SubjectModel.fromEntity(s));
  }

  @override
  Future<void> delete(String id) async {
    // Hard delete. Callers are responsible for first deleting any topics
    // that reference this subject (see TopicCommands.deleteSubjectCascading).
    await _store.subjects.delete(id);
  }

  @override
  Stream<List<Subject>> watch() async* {
    yield all();
    yield* _store.subjects.watch().map((_) => all());
  }
}
