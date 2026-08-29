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

    // Empty database on launch: offer to restore the automatic snapshot
    // rather than dropping the user into an empty app.
    if (StorageService.instance.isEmpty) {
      await _offerRestore();
    }

    if (!mounted) return;
    context.go('/today');
  }

  Future<void> _offerRestore() async {
    // Two possible sources, checked in order of usefulness:
    //   • the user's chosen folder — survives an uninstall, so this is the one
    //     that matters after reinstalling;
    //   • the app-private snapshot — only survives "clear app data".
    final fromFolder = await BackupService.instance.folderHasBackup();
    final fromApp = await BackupService.instance.hasAutoBackup();
    if (!fromFolder && !fromApp) return;
    if (!mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore your data?'),
        content: Text(
          fromFolder
              ? 'No topics found, but there is a RecallDay backup in the '
                  'folder you chose. Would you like to restore it?'
              : 'No topics found, but RecallDay has a saved copy on this '
                  'device. Would you like to restore it?',
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
    if (restore != true) return;

    if (mounted) setState(() => _status = 'Restoring…');
    final summary = fromFolder
        ? await BackupService.instance.restoreFromFolder()
        : await BackupService.instance.autoRestoreIfEmpty();
    if (summary == null || summary.isEmpty) {
      if (mounted) setState(() => _status = 'Nothing to restore');
      await Future<void>.delayed(const Duration(milliseconds: 700));
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
