import 'package:hive_flutter/hive_flutter.dart';

import '../data/models/review_model.dart';
import '../data/models/subject_model.dart';
import '../data/models/topic_model.dart';

/// Hive bootstrap + box accessors.
///
/// Storage footprint notes:
///   • Each Subject record: ~120 bytes on disk.
///   • Each Topic record: ~280 bytes (depends on notes length).
///   • Each Review record: ~70 bytes.
/// 1000 topics + 10000 reviews ≈ 1 MB on-disk. Fits comfortably on any phone.
///
/// Hive uses an append-only log, so deleted records leave gaps in the file
/// until it is rewritten. Hive does that automatically once enough entries
/// have been deleted, which is why there is no manual "compact storage"
/// action — the button that used to exist could only ever do early what the
/// database already does on its own.
class StorageService {
  static const String subjectsBox = 'subjects';
  static const String topicsBox = 'topics';
  static const String reviewsBox = 'reviews';
  static const String prefsBox = 'prefs';

  StorageService._();
  static final StorageService instance = StorageService._();

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SubjectModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(TopicModelAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(ReviewModelAdapter());
    }

    await Hive.openBox<SubjectModel>(subjectsBox);
    await Hive.openBox<TopicModel>(topicsBox);
    await Hive.openBox<ReviewModel>(reviewsBox);
    await Hive.openBox(prefsBox);
  }

  Box<SubjectModel> get subjects => Hive.box<SubjectModel>(subjectsBox);
  Box<TopicModel> get topics => Hive.box<TopicModel>(topicsBox);
  Box<ReviewModel> get reviews => Hive.box<ReviewModel>(reviewsBox);
  Box get prefs => Hive.box(prefsBox);

  /// True when there is nothing to lose — used at startup to decide whether to
  /// pull a backup back in after a reinstall. Reviews are deliberately excluded:
  /// orphan review rows without subjects or topics are not worth preserving.
  bool get isEmpty => subjects.isEmpty && topics.isEmpty;

}
