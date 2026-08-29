import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../data/models/topic_model.dart';
import '../data/models/subject_model.dart';
import '../data/models/review_model.dart';
import '../domain/entities/topic.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Daily background sweep that re-arms alarms killed by OEM optimizers.
/// Runs via WorkManager (~24h cadence, Android schedules opportunistically).
///
/// Why we need this on top of flutter_local_notifications' BootReceiver:
/// the boot receiver only fires on device restart. OEM "battery savers" can
/// kill scheduled alarms while the device is awake. WorkManager's periodic
/// task is the only Android-blessed way to wake up reliably for non-foreground
/// work without abusing AlarmManager.
const String kPeriodicTaskName = 'recallday_periodic_resync';
const String kPeriodicTaskTag = 'recallday';

@pragma('vm:entry-point')
void schedulerCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    try {
      // The background isolate must initialize Hive on its own.
      await Hive.initFlutter();
      _registerAdapters();

      final box = await Hive.openBox<TopicModel>(StorageService.topicsBox);
      // Subject names go into the notification body ("Algorithms · Dijkstra"),
      // so the sweep needs this box open too.
      final subjectBox =
          await Hive.openBox<SubjectModel>(StorageService.subjectsBox);
      final names = {for (final s in subjectBox.values) s.id: s.name};

      await NotificationService.instance.init();

      final active = box.values
          .map((m) => m.toEntity())
          .where((t) => t.status == TopicStatus.active)
          .toList();
      await NotificationService.instance
          .scheduleAllFrom(active, subjectNames: names);

      debugPrint('[scheduler_worker] re-armed ${active.length} active topic alarms');
      return true;
    } catch (e, st) {
      debugPrint('[scheduler_worker] failed: $e\n$st');
      return false;
    }
  });
}

void _registerAdapters() {
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(SubjectModelAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TopicModelAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(ReviewModelAdapter());
}

class SchedulerBootstrap {
  static Future<void> initWorkmanager() async {
    await Workmanager().initialize(
      schedulerCallbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    // Defaults are right for an offline-only use case: no network or charging
    // constraints, and periodic tasks default to KEEP so re-registering on
    // every launch doesn't reset the 12h clock.
    //
    // This only runs if WorkManager initialized successfully — see the note in
    // AndroidManifest.xml about the androidx.startup initializer, whose removal
    // used to make this throw on every launch.
    await Workmanager().registerPeriodicTask(
      kPeriodicTaskName,
      kPeriodicTaskName,
      frequency: const Duration(hours: 12),
      tag: kPeriodicTaskTag,
    );
  }
}
