import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'models/subtopic_model.dart';
import 'models/topic_model.dart';

/// Give every subtopic a parent topic.
///
/// The tree used to be Subject → Topic, and what was called a topic is
/// what the app now calls a subtopic: the scheduled leaf. Rather than move
/// those records — which would have meant rewriting every id that reviews,
/// attachment folders and notification blocks are keyed by — the upgrade
/// leaves them exactly where they are and builds the missing layer above them.
///
/// Each unparented subtopic gets a topic of its own, named after it, so a user
/// upgrading sees the library they already had with one more level of nesting,
/// not a pile of unrelated leaves swept into a "General" bucket.
///
/// Two properties matter more than the shape of the result:
///
///   • **Idempotent.** It only ever touches a subtopic whose [topicId] is
///     missing, so running it on every launch costs one pass over the box and
///     changes nothing once the tree is whole.
///   • **Self-healing.** A [topicId] pointing at a topic that isn't there —
///     which a partial restore, or a backup written by a build in between, can
///     produce — is treated the same as a missing one. That keeps a subtopic
///     from becoming unreachable in the UI, which is the one failure mode here
///     that looks like data loss without being it.
///
/// Returns the number of topics created.
Future<int> runHierarchyMigration({
  required Box<TopicModel> topics,
  required Box<SubtopicModel> subtopics,
}) async {
  try {
    const uuid = Uuid();
    var created = 0;

    for (final key in subtopics.keys.toList()) {
      final s = subtopics.get(key);
      if (s == null) continue;
      if (s.topicId.isNotEmpty && topics.containsKey(s.topicId)) continue;

      final topic = TopicModel(
        id: uuid.v4(),
        subjectId: s.subjectId,
        title: s.title,
        createdAt: s.createdAt,
      );
      await topics.put(topic.id, topic);
      s.topicId = topic.id;
      await subtopics.put(key, s);
      created++;
    }

    if (created > 0) {
      debugPrint('[migration] created $created topic(s) for existing subtopics');
    }
    return created;
  } catch (e, st) {
    // A failed migration must not stop the app opening: the subtopics are all
    // still there, and the next launch tries again.
    debugPrint('[migration] hierarchy migration failed: $e\n$st');
    return 0;
  }
}
