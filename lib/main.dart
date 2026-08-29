import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/providers.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'services/scheduler_worker.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // 1) Local storage (Hive boxes for subjects, topics, reviews, prefs)
  await StorageService.instance.init();

  // 2) If this is a fresh install (or a reinstall) and a backup is sitting in
  //    shared storage, pull it back in before the first frame so the user
  //    doesn't see an empty app and assume the data is gone.
  await BackupService.instance.autoRestoreIfEmpty();

  // 3) Local notifications + timezone
  await NotificationService.instance.init();

  // 4) Background re-arm worker (handles OEM alarm cleanup + boot recovery).
  //    Wrapped in try/catch so a Workmanager init failure on a quirky OEM
  //    doesn't take down the app launch.
  try {
    await SchedulerBootstrap.initWorkmanager();
  } catch (e) {
    debugPrint('[main] workmanager init skipped: $e');
  }

  runApp(const ProviderScope(child: _AppRoot()));
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();
  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  @override
  void initState() {
    super.initState();
    NotificationService.onAction = (topicId, action) {
      final router = ref.read(routerProvider);
      router.go('/topic/$topicId?action=${action ?? ''}');
    };

    // Re-arm every active topic's alarms on each cold start. Android drops
    // scheduled alarms on reboot, app update and OEM battery sweeps; without
    // this, a dropped alarm was never rescheduled until the user happened to
    // edit or review that topic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(topicCommandsProvider).reArmAllNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'RecallDay',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(),
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
