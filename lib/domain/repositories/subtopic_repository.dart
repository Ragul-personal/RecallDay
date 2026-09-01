import '../entities/review.dart';
import '../entities/subtopic.dart';

abstract class SubtopicRepository {
  List<Subtopic> all();
  List<Subtopic> bySubject(String subjectId);
  List<Subtopic> byTopic(String topicId);
  Subtopic? byId(String id);
  Future<void> upsert(Subtopic s);
  Future<void> delete(String id);
  Stream<List<Subtopic>> watch();

  Future<void> recordReview(Review r);
  List<Review> reviewsForSubtopic(String subtopicId);
  List<Review> allReviews();

  /// Remove every review belonging to [subtopicId]. Deleting a subtopic without
  /// this leaves its reviews behind forever, inflating the streak counter and
  /// the analytics page with history the user can no longer see.
  Future<int> deleteReviewsForSubtopic(String subtopicId);
}
