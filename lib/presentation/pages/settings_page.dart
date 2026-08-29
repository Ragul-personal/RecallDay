import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../providers/providers.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/delete_confirm.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  PermissionReport? _perms;
  DateTime? _lastAuto;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final perms = await NotificationService.instance.permissionStatus();
    final saved = await BackupService.instance.lastAutoBackupAt();
    if (!mounted) return;
    setState(() {
      _perms = perms;
      _lastAuto = saved;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _details(String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SelectableText(
              body,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          children: [
            _appearance(),
            _reminders(),
            _backup(),
            _data(),
            _about(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- appearance

  Widget _appearance() {
    final mode = ref.watch(themeModeProvider);
    return _Group(
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined, size: 18),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined, size: 18),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined, size: 18),
                label: Text('Auto'),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              ref.read(themeModeProvider.notifier).set(s.first);
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- reminders

  Widget _reminders() {
    final p = _perms;
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final success =
        light ? StatusColors.successLight : StatusColors.successDark;
    final warning =
        light ? StatusColors.warningLight : StatusColors.warningDark;

    // Nothing to fix once both permissions are held — the button that used to
    // sit here always reported "Permissions refreshed" whether or not anything
    // had changed, which made it look broken. It now appears only when there
    // is genuinely something to grant.
    final needsAction = p != null && (!p.canNotify || !p.exactAlarmGranted);

    return _Group(
      title: 'Reminders',
      children: [
        if (p != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.md,
            ),
            child: _StatusBanner(
              ok: p.canNotify && p.exactAlarmGranted,
              color: !p.canNotify
                  ? cs.error
                  : p.exactAlarmGranted
                      ? success
                      : warning,
              title: !p.canNotify
                  ? 'Reminders are blocked'
                  : p.exactAlarmGranted
                      ? 'Reminders are on and exact'
                      : 'Reminders are on, but may run late',
              message: !p.canNotify
                  ? 'Android is not letting RecallDay post notifications, so '
                      'no reminder will ever appear.'
                  : p.exactAlarmGranted
                      ? 'Your reminders will fire at the time you set.'
                      : 'Exact alarms are off, so Android may batch reminders '
                          'and deliver them a few minutes late.',
            ),
          ),
        if (needsAction)
          ListTile(
            leading: Icon(Icons.notifications_active_outlined, color: cs.primary),
            title: Text(
              p.canNotify ? 'Allow exact alarms' : 'Allow notifications',
            ),
            subtitle: const Text('Opens the Android permission screen'),
            onTap: _busy ? null : _requestPermissions,
          ),
        const ListTile(
          leading: Icon(Icons.battery_alert_outlined),
          title: Text('If reminders stop arriving'),
          subtitle: Text(
            'On Xiaomi, OnePlus and Samsung, exempt RecallDay from battery '
            'optimisation in Android Settings → Apps → RecallDay → Battery. '
            'RecallDay re-schedules its alarms every time you open it, so '
            'they recover on their own once it is allowed to run.',
          ),
        ),
        // Kept for future diagnosis but hidden from release builds — the
        // notification path is working, so a test button is just clutter.
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Send a test reminder (debug)'),
            onTap: () async {
              final ok =
                  await NotificationService.instance.showTestNotification();
              _toast(ok ? 'Test reminder sent' : 'Android refused it');
            },
          ),
      ],
    );
  }

  Future<void> _requestPermissions() async {
    final before = _perms;
    final report = await NotificationService.instance.requestPermissions();
    NotificationService.instance.invalidatePermissionCache();
    // A newly granted exact-alarm permission only takes effect on alarms
    // scheduled from now on, so re-arm what's already pending.
    await ref.read(topicCommandsProvider).reArmAllNotifications();
    await _refreshStatus();
    if (!mounted) return;

    if (report.notificationsGranted && report.exactAlarmGranted) {
      _toast('All set — reminders will fire on time');
      return;
    }
    if (!report.notificationsGranted) {
      // Android stops prompting after two denials; the settings screen is
      // then the only way in, so say so rather than silently doing nothing.
      final stuck =
          await NotificationService.instance.notificationsPermanentlyDenied();
      if (!mounted) return;
      if (stuck || before?.notificationsGranted == false) {
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Notifications are blocked'),
            content: const Text(
              'Android will not show the permission prompt again for this app. '
              'Open RecallDay in Android Settings and turn Notifications on.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
        if (open == true) {
          await NotificationService.instance.openSystemSettings();
        }
        return;
      }
      _toast('Notifications are still blocked');
      return;
    }
    _toast('Notifications on · exact alarms still off');
  }

  // ----------------------------------------------------------------- backup

  Widget _backup() {
    final light = Theme.of(context).brightness == Brightness.light;
    final success =
        light ? StatusColors.successLight : StatusColors.successDark;
    final saved = _lastAuto;

    return _Group(
      title: 'Backup',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: _StatusBanner(
            ok: saved != null,
            color: success,
            title: saved == null
                ? 'Saving automatically'
                : 'Saved automatically',
            message: saved == null
                ? 'Every change is saved on this device as you make it.'
                : 'Every change is saved on this device as you make it — last '
                    'at ${DateLabels.time(saved)}. Android deletes this copy '
                    'if the app is uninstalled, so export a file to keep it.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('Export backup file'),
          subtitle: const Text(
            'One .zip with everything, including attachments — save it to '
            'Drive, Files, or send it to yourself',
          ),
          onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final err = await BackupService.instance.exportArchive();
                  if (mounted) setState(() => _busy = false);
                  if (!mounted) return;
                  if (err != null) await _details('Export failed', err);
                },
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Import backup file'),
          subtitle: const Text('Pick a .zip or .json backup to restore'),
          onTap: _busy ? null : _import,
        ),
      ],
    );
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final summary = await BackupService.instance.importArchive(merge: true);
      await ref.read(topicCommandsProvider).reArmAllNotifications();
      await _refreshStatus();
      if (!mounted) return;
      if (summary.isEmpty) {
        await _details(
          'Nothing restored',
          'That file was read but contained no subjects or topics.',
        );
      } else {
        _toast('Restored $summary');
      }
    } on BackupCancelled {
      // User dismissed the picker; nothing to report.
    } catch (e) {
      if (mounted) await _details('Import failed', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------- data

  Widget _data() {
    final cs = Theme.of(context).colorScheme;
    return _Group(
      title: 'Data',
      children: [
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: cs.error),
          title: Text('Reset all data', style: TextStyle(color: cs.error)),
          subtitle: const Text('Deletes everything on this device'),
          onTap: () async {
            final ok = await confirmDelete(
              context,
              title: 'Reset all data?',
              message: 'This deletes every subject, topic and review on this '
                  'device. Your backup file is not touched, so you can '
                  'restore from it afterwards.',
              confirmLabel: 'Reset',
            );
            if (!ok) return;
            await NotificationService.instance.cancelAll();
            await StorageService.instance.subjects.clear();
            await StorageService.instance.topics.clear();
            await StorageService.instance.reviews.clear();
            _toast('All data cleared');
          },
        ),
      ],
    );
  }

  Widget _about() {
    final tt = Theme.of(context).textTheme;
    return _Group(
      title: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              const AppLogo(size: 116, elevated: false),
              const SizedBox(height: AppSpacing.lg),
              Text('Remember today. Master tomorrow.', style: tt.labelSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Everything stays on this device — no accounts, no analytics.',
                textAlign: TextAlign.center,
                style: tt.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tinted status strip used by the reminder and backup sections.
class _StatusBanner extends StatelessWidget {
  final bool ok;
  final Color color;
  final String title;
  final String message;

  const _StatusBanner({
    required this.ok,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(message, style: tt.labelSmall?.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xxl,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Text(
            title.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}
