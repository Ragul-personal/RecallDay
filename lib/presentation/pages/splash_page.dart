import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';

import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../providers/providers.dart';
import '../widgets/app_logo.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});
  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  String? _status;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 400), _bootstrap);
  }

  Future<void> _bootstrap() async {
    // Local-only build: no auth gate, just permissions and a possible restore.
    await NotificationService.instance.requestPermissions();

    // Empty database — either a first run or a reinstall. `main()` already
    // tried an auto-restore, but on a reinstall the storage permission has
    // been reset, so the backup file in shared storage was unreadable then.
    // Ask for access now and try again, so a reinstall brings the user's
    // topics back instead of dropping them into an empty app.
    if (StorageService.instance.isEmpty) {
      await _offerRestore();
    }

    if (!mounted) return;
    context.go('/today');
  }

  Future<void> _offerRestore() async {
    // We can't just probe for the backup file: on Android 11+ an unreadable
    // path and a missing one are indistinguishable (File.exists() returns
    // false either way), so "is there a backup?" can't be answered without
    // first holding the permission. Rather than shove a returning user AND a
    // brand-new user through a full-screen system settings page, ask.
    if (!mounted) return;
    final wantsRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore your data?'),
        content: const Text(
          'No topics found on this device.\n\n'
          'If you have used RecallDay before, it can bring your subjects, '
          'topics and review history back from the backup file on your phone '
          'storage. Android needs file access to read it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Start fresh'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (wantsRestore != true) return;
    if (mounted) setState(() => _status = 'Looking for a backup…');

    if (await BackupService.instance.findBackupFile() == null) {
      await BackupService.instance.requestStoragePermission();
    }

    final summary = await BackupService.instance.autoRestoreIfEmpty();
    if (summary == null || summary.isEmpty) {
      if (mounted) setState(() => _status = 'No backup found');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return;
    }

    // Restored topics need their alarms scheduled from scratch — a backup
    // carries data, not OS-level alarms.
    await ref.read(topicCommandsProvider).reArmAllNotifications();
    if (mounted) setState(() => _status = 'Restored $summary');
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The artwork already carries the wordmark and tagline, so there's
            // no separate "RecallDay" text here — that would just duplicate it.
            const AppLogo(size: 176)
                .animate()
                .fadeIn(duration: AppMotion.slow, curve: AppMotion.curve)
                .scale(
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1, 1),
                  duration: AppMotion.slow,
                  curve: AppMotion.curve,
                ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: AppMotion.base,
              child: Text(
                _status ?? 'Remember today. Master tomorrow.',
                key: ValueKey(_status),
                textAlign: TextAlign.center,
                style: tt.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
