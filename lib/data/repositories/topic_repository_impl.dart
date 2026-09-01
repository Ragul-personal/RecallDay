import 'dart:async';
import '../../domain/entities/topic.dart';
import '../../domain/repositories/topic_repository.dart';
import '../models/topic_model.dart';
import '../../services/storage_service.dart';

class TopicRepositoryImpl implements TopicRepository {
  final _store = StorageService.instance;

  @override
  List<Topic> all() => _store.topics.values.map((m) => m.toEntity()).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  @override
  List<Topic> bySubject(String subjectId) => _store.topics.values
      .where((m) => m.subjectId == subjectId)
      .map((m) => m.toEntity())
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  @override
  Topic? byId(String id) => _store.topics.get(id)?.toEntity();

  @override
  Future<void> upsert(Topic t) async {
    await _store.topics.put(t.id, TopicModel.fromEntity(t));
  }

  @override
  Future<void> delete(String id) async {
    // Hard delete. Callers are responsible for first deleting any subtopics
    // that reference this topic (see TopicCommands.deleteTopicCascading).
    await _store.topics.delete(id);
  }

  @override
  Stream<List<Topic>> watch() async* {
    yield all();
    yield* _store.topics.watch().map((_) => all());
  }
}
