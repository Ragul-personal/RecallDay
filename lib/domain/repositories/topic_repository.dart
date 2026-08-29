import '../entities/topic.dart';
import '../entities/review.dart';

abstract class TopicRepository {
  List<Topic> all();
  List<Topic> bySubject(String subjectId);
  Topic? byId(String id);
  Future<void> upsert(Topic t);
  Future<void> delete(String id);
  Stream<List<Topic>> watch();

  Future<void> recordReview(Review r);
  List<Review> reviewsForTopic(String topicId);
  List<Review> allReviews();

  /// Remove every review belonging to [topicId]. Deleting a topic without this
  /// leaves its reviews behind forever, inflating the streak counter and the
  /// analytics page with history for topics the user can no longer see.
  Future<int> deleteReviewsForTopic(String topicId);
}
