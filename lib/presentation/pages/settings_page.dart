import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
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
  BackupLocation? _location;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final perms = await NotificationService.instance.permissionStatus();
    final loc = await BackupService.instance.resolveLocation(refresh: true);
    if (!mounted) return;
    setState(() {
      _perms = perms;
      _location = loc;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          children: [
            _appearance(),
            _notifications(),
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

  // ---------------------------------------------------------- notifications

  Widget _notifications() {
    final p = _perms;
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final success =
        light ? StatusColors.successLight : StatusColors.successDark;

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
              ok: p.canNotify,
              color: p.canNotify ? success : cs.error,
              title: p.canNotify ? 'Reminders are on' : 'Reminders are blocked',
              message: !p.canNotify
                  ? 'Android is not letting RecallDay post notifications. '
                      'Tap "Grant permissions" below.'
                  : p.exactAlarmGranted
                      ? 'Exact alarms allowed — reminders fire on time.'
                      : 'Exact alarms are off, so Android may deliver reminders '
                          'a few minutes late. Turn on "Alarms & reminders" to fix.',
            ),
          ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Grant permissions'),
          subtitle: const Text('Open the system permission screens'),
          onTap: _busy
              ? null
              : () async {
                  await NotificationService.instance.requestPermissions();
                  NotificationService.instance.invalidatePermissionCache();
                  await ref.read(topicCommandsProvider).reArmAllNotifications();
                  await _refreshStatus();
                  _toast('Permissions refreshed');
                },
        ),
        ListTile(
          leading: const Icon(Icons.send_outlined),
          title: const Text('Send a test reminder'),
          subtitle: const Text('Check it appears with sound'),
          onTap: _busy
              ? null
              : () async {
                  final ok =
                      await NotificationService.instance.showTestNotification();
                  _toast(ok
                      ? 'Sent — check your notification bar'
                      : 'Android refused it. Grant permissions first.');
                },
        ),
        ListTile(
          leading: const Icon(Icons.alarm_on_outlined),
          title: const Text('Re-arm all reminders'),
          subtitle: const Text('Reschedule every active topic'),
          onTap: _busy
              ? null
              : () async {
                  await ref.read(topicCommandsProvider).reArmAllNotifications();
                  _toast('Reminders rescheduled');
                },
        ),
        const ListTile(
          leading: Icon(Icons.battery_alert_outlined),
          title: Text('Battery optimisation'),
          subtitle: Text(
            'On Xiaomi, OnePlus and Samsung, exempt RecallDay from battery '
            'optimisation in Android Settings → Apps → RecallDay → Battery.',
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- backup

  Widget _backup() {
    final loc = _location;
    final durable = loc?.survivesUninstall ?? false;
    final light = Theme.of(context).brightness == Brightness.light;
    final success =
        light ? StatusColors.successLight : StatusColors.successDark;
    final warning =
        light ? StatusColors.warningLight : StatusColors.warningDark;

    return _Group(
      title: 'Backup',
      children: [
        if (loc != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.md,
            ),
            child: _StatusBanner(
              ok: durable,
              color: durable ? success : warning,
              title: durable
                  ? 'Backups survive uninstall'
                  : 'Backups will not survive uninstall',
              message: durable
                  ? 'Saved to ${loc.label}. Reinstalling restores this '
                      'automatically.'
                  : 'Android is only letting RecallDay write to its own sandbox '
                      '(${loc.label}), which is deleted on uninstall.',
            ),
          ),
        if (!durable)
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Allow shared storage'),
            subtitle: const Text('Needed to back up outside the app sandbox'),
            onTap: _busy
                ? null
                : () async {
                    await BackupService.instance.requestStoragePermission();
                    await _refreshStatus();
                    if (_location?.survivesUninstall == true) {
                      await BackupService.instance.flush();
                      _toast('Shared storage enabled — backup written');
                    } else {
                      _toast('Still sandboxed — grant "All files access" '
                          'in Android settings');
                    }
                  },
          ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Back up now'),
          subtitle: const Text('Write a snapshot of everything'),
          onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await BackupService.instance.flush();
                  if (mounted) setState(() => _busy = false);
                  await _refreshStatus();
                  if (!mounted) return;
                  if (r.ok) {
                    _toast('Backed up ${r.topics} topics '
                        'to ${r.location?.label}');
                  } else {
                    // A snackbar truncates the diagnostic, which is the only
                    // thing that makes a failure actionable.
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Backup failed'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            r.error ?? 'Unknown error',
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
                  }
                },
        ),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore from backup'),
          subtitle: const Text('Merge the saved snapshot back in'),
          onTap: _busy ? null : _restore,
        ),
        ListTile(
          leading: const Icon(Icons.copy_all_outlined),
          title: const Text('Copy backup as text'),
          subtitle: const Text('Paste into a note as a second copy'),
          onTap: () async {
            await Clipboard.setData(
              ClipboardData(text: BackupService.instance.buildSnapshotJson()),
            );
            _toast('Copied to clipboard');
          },
        ),
      ],
    );
  }

  Future<void> _restore() async {
    final file = await BackupService.instance.findBackupFile();
    if (!mounted) return;
    if (file == null) {
      _toast('No backup file found');
      return;
    }

    final ok = await confirmDelete(
      context,
      title: 'Restore backup?',
      message: 'This merges the snapshot at ${file.path} into your current '
          'data. Topics with the same id are overwritten.',
      confirmLabel: 'Restore',
      destructive: false,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final summary = await BackupService.instance.restoreFromFile(merge: true);
      await ref.read(topicCommandsProvider).reArmAllNotifications();
      if (!mounted) return;
      _toast(summary == null ? 'Nothing to restore' : 'Restored $summary');
    } catch (e) {
      _toast('Restore failed: $e');
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
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Compact storage'),
          subtitle: const Text('Reclaim space from deleted topics'),
          onTap: () async {
            await StorageService.instance.compactAll();
            _toast('Storage compacted');
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: cs.error),
          title: Text('Reset all data', style: TextStyle(color: cs.error)),
          subtitle: const Text('Your backup file is left untouched'),
          onTap: () async {
            final ok = await confirmDelete(
              context,
              title: 'Reset all data?',
              message: 'This deletes every subject, topic and review on this '
                  'device. Your backup file is not touched.',
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
            ok
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
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
