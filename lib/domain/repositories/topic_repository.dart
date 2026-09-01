import '../entities/topic.dart';

abstract class TopicRepository {
  List<Topic> all();
  List<Topic> bySubject(String subjectId);
  Topic? byId(String id);
  Future<void> upsert(Topic t);
  Future<void> delete(String id);
  Stream<List<Topic>> watch();
}
