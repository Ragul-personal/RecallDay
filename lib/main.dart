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

  // Every step below is individually guarded, and runApp() ALWAYS runs.
  //
  // This used to be a chain of bare `await`s. Anything that threw — and a
  // stripped notification icon in the release build did exactly that — escaped
  // main() before runApp(), so the app launched to a black screen with no way
  // to tell what went wrong. A broken subsystem should cost you that feature,
  // not the whole app.

  // 1) Local storage (Hive boxes for subjects, topics, reviews, prefs).
  //    The one genuinely fatal dependency: with no database there is no app.
  String? fatal;
  try {
    await StorageService.instance.init();
  } catch (e, st) {
    debugPrint('[main] storage init FAILED: $e\n$st');
    fatal = 'Could not open local storage.\n\n$e';
  }

  if (fatal == null) {
    // 2) If this is a fresh install (or a reinstall) and a backup is sitting in
    //    shared storage, pull it back in before the first frame so the user
    //    doesn't see an empty app and assume the data is gone.
    try {
      await BackupService.instance.autoRestoreIfEmpty();
    } catch (e) {
      debugPrint('[main] auto-restore skipped: $e');
    }

    // 3) Local notifications + timezone. Non-fatal: the app is still usable
    //    for reviewing, it just won't remind you.
    try {
      await NotificationService.instance.init();
    } catch (e) {
      debugPrint('[main] notification init skipped: $e');
    }

    // 4) Background re-arm worker (handles OEM alarm cleanup + boot recovery).
    try {
      await SchedulerBootstrap.initWorkmanager();
    } catch (e) {
      debugPrint('[main] workmanager init skipped: $e');
    }
  }

  runApp(fatal == null
      ? const ProviderScope(child: _AppRoot())
      : _StartupErrorApp(message: fatal));
}

/// Shown instead of a black screen when startup genuinely cannot continue, so
/// the failure is legible on-device without needing a USB cable and `adb`.
class _StartupErrorApp extends StatelessWidget {
  final String message;
  const _StartupErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(),
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'RecallDay could not start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(child: SelectableText(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
