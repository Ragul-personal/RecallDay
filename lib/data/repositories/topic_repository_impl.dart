import 'dart:async';
import '../../domain/entities/topic.dart';
import '../../domain/entities/review.dart';
import '../../domain/repositories/topic_repository.dart';
import '../models/review_model.dart';
import '../models/topic_model.dart';
import '../../services/storage_service.dart';

class TopicRepositoryImpl implements TopicRepository {
  final _store = StorageService.instance;

  @override
  List<Topic> all() => _store.topics.values.map((m) => m.toEntity()).toList();

  @override
  List<Topic> bySubject(String subjectId) => _store.topics.values
      .where((m) => m.subjectId == subjectId)
      .map((m) => m.toEntity())
      .toList();

  @override
  Topic? byId(String id) => _store.topics.get(id)?.toEntity();

  @override
  Future<void> upsert(Topic t) async {
    await _store.topics.put(t.id, TopicModel.fromEntity(t));
  }

  @override
  Future<void> delete(String id) async {
    await _store.topics.delete(id);
  }

  @override
  Stream<List<Topic>> watch() async* {
    yield all();
    yield* _store.topics.watch().map((_) => all());
  }

  @override
  Future<void> recordReview(Review r) async {
    await _store.reviews.put(r.id, ReviewModel.fromEntity(r));
  }

  @override
  List<Review> reviewsForTopic(String topicId) => _store.reviews.values
      .where((m) => m.topicId == topicId)
      .map((m) => m.toEntity())
      .toList();

  @override
  List<Review> allReviews() =>
      _store.reviews.values.map((m) => m.toEntity()).toList();

  @override
  Future<int> deleteReviewsForTopic(String topicId) async {
    // Collect keys first — deleting while iterating `values` would mutate the
    // collection underneath the iterator.
    final keys = _store.reviews.keys
        .where((k) => _store.reviews.get(k)?.topicId == topicId)
        .toList();
    if (keys.isEmpty) return 0;
    await _store.reviews.deleteAll(keys);
    return keys.length;
  }
}
