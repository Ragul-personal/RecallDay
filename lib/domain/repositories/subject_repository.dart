import '../entities/subject.dart';

abstract class SubjectRepository {
  List<Subject> all();
  Subject? byId(String id);
  Future<void> upsert(Subject s);
  Future<void> delete(String id);
  Stream<List<Subject>> watch();
}
