import 'dart:async';
import '../../domain/entities/review.dart';
import '../../domain/entities/subtopic.dart';
import '../../domain/repositories/subtopic_repository.dart';
import '../models/review_model.dart';
import '../models/subtopic_model.dart';
import '../../services/storage_service.dart';

class SubtopicRepositoryImpl implements SubtopicRepository {
  final _store = StorageService.instance;

  @override
  List<Subtopic> all() =>
      _store.subtopics.values.map((m) => m.toEntity()).toList();

  @override
  List<Subtopic> bySubject(String subjectId) => _store.subtopics.values
      .where((m) => m.subjectId == subjectId)
      .map((m) => m.toEntity())
      .toList();

  @override
  List<Subtopic> byTopic(String topicId) => _store.subtopics.values
      .where((m) => m.topicId == topicId)
      .map((m) => m.toEntity())
      .toList();

  @override
  Subtopic? byId(String id) => _store.subtopics.get(id)?.toEntity();

  @override
  Future<void> upsert(Subtopic s) async {
    await _store.subtopics.put(s.id, SubtopicModel.fromEntity(s));
  }

  @override
  Future<void> delete(String id) async {
    await _store.subtopics.delete(id);
  }

  @override
  Stream<List<Subtopic>> watch() async* {
    yield all();
    yield* _store.subtopics.watch().map((_) => all());
  }

  @override
  Future<void> recordReview(Review r) async {
    await _store.reviews.put(r.id, ReviewModel.fromEntity(r));
  }

  @override
  List<Review> reviewsForSubtopic(String subtopicId) => _store.reviews.values
      .where((m) => m.subtopicId == subtopicId)
      .map((m) => m.toEntity())
      .toList();

  @override
  List<Review> allReviews() =>
      _store.reviews.values.map((m) => m.toEntity()).toList();

  @override
  Future<int> deleteReviewsForSubtopic(String subtopicId) async {
    // Collect keys first — deleting while iterating `values` would mutate the
    // collection underneath the iterator.
    final keys = _store.reviews.keys
        .where((k) => _store.reviews.get(k)?.subtopicId == subtopicId)
        .toList();
    if (keys.isEmpty) return 0;
    await _store.reviews.deleteAll(keys);
    return keys.length;
  }
}
