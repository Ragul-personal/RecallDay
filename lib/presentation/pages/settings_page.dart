import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../providers/providers.dart';
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
        child: ListView(children: [
          ..._notificationSection(),
          ..._backupSection(),
          ..._dataSection(),
          ..._aboutSection(),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ notifications

  List<Widget> _notificationSection() {
    final p = _perms;
    return [
      _Section(title: 'Notifications', children: [
        ListTile(
          leading: Icon(
            p == null
                ? Icons.hourglass_empty
                : p.canNotify
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
            color: p == null
                ? null
                : p.canNotify
                    ? const Color(0xFF8FD9C0)
                    : Theme.of(context).colorScheme.error,
          ),
          title: Text(p == null
              ? 'Checking permissions…'
              : p.canNotify
                  ? 'Reminders are allowed'
                  : 'Reminders are blocked'),
          subtitle: Text(
            p == null
                ? ''
                : !p.canNotify
                    ? 'Android is not letting RecallDay post notifications. '
                        'Tap "Grant permissions" below.'
                    : p.exactAlarmGranted
                        ? 'Exact alarms allowed — reminders fire on time.'
                        : 'Exact alarms are off, so Android may batch reminders '
                            'and deliver them a few minutes late. Turn on '
                            '"Alarms & reminders" for RecallDay to fix that.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
          ),
          isThreeLine: p != null,
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
                  // Re-arm with the (possibly upgraded) exact-alarm capability.
                  await ref
                      .read(topicCommandsProvider)
                      .reArmAllNotifications();
                  await _refreshStatus();
                  _toast('Permissions refreshed');
                },
        ),
        ListTile(
          leading: const Icon(Icons.send_outlined),
          title: const Text('Send a test reminder'),
          subtitle: const Text('Check the notification appears with sound'),
          onTap: _busy
              ? null
              : () async {
                  final ok = await NotificationService.instance
                      .showTestNotification();
                  _toast(ok
                      ? 'Test reminder sent — check your notification bar'
                      : 'Android refused the notification. Grant permissions first.');
                },
        ),
        ListTile(
          leading: const Icon(Icons.alarm_on_outlined),
          title: const Text('Re-arm all reminders'),
          subtitle: const Text('Reschedule alarms for every active topic'),
          onTap: _busy
              ? null
              : () async {
                  await ref
                      .read(topicCommandsProvider)
                      .reArmAllNotifications();
                  _toast('Reminders rescheduled');
                },
        ),
        const ListTile(
          leading: Icon(Icons.battery_alert_outlined),
          title: Text('Battery optimization'),
          subtitle: Text(
            'For reliable reminders on Xiaomi/OnePlus/Samsung, exempt RecallDay '
            'from battery optimization in Android Settings → Apps → RecallDay → Battery.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
          ),
        ),
      ]),
    ];
  }

  // ------------------------------------------------------------------ backup

  List<Widget> _backupSection() {
    final loc = _location;
    final durable = loc?.survivesUninstall ?? false;
    return [
      _Section(title: 'Backup & restore', children: [
        ListTile(
          leading: Icon(
            durable ? Icons.verified_outlined : Icons.warning_amber_outlined,
            color: durable
                ? const Color(0xFF8FD9C0)
                : const Color(0xFFE0A878),
          ),
          title: Text(loc == null
              ? 'Checking storage…'
              : durable
                  ? 'Backups survive uninstall'
                  : 'Backups will NOT survive uninstall'),
          subtitle: Text(
            loc == null
                ? ''
                : durable
                    ? 'Saved to ${loc.label}. Reinstalling RecallDay restores '
                        'this automatically.'
                    : 'Android is only letting RecallDay write to its own '
                        'sandbox (${loc.label}), which is deleted on uninstall. '
                        'Tap "Allow shared storage" to fix this.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
          ),
          isThreeLine: loc != null,
        ),
        if (!durable)
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Allow shared storage'),
            subtitle: const Text(
                'Needed to write a backup outside the app sandbox'),
            onTap: _busy
                ? null
                : () async {
                    await BackupService.instance.requestStoragePermission();
                    await _refreshStatus();
                    if (_location?.survivesUninstall == true) {
                      // Immediately lay down a durable copy in the new location.
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
          subtitle: const Text('Write a JSON snapshot of everything'),
          onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await BackupService.instance.flush();
                  if (mounted) setState(() => _busy = false);
                  await _refreshStatus();
                  _toast(r.ok
                      ? 'Backed up ${r.topics} topics to ${r.location?.label}'
                      : 'Backup failed: ${r.error}');
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
          title: const Text('Copy JSON to clipboard'),
          subtitle: const Text('Paste into a note or email as a second copy'),
          onTap: () async {
            await Clipboard.setData(
                ClipboardData(text: BackupService.instance.buildSnapshotJson()));
            _toast('Copied to clipboard');
          },
        ),
      ]),
    ];
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

  // -------------------------------------------------------------------- data

  List<Widget> _dataSection() {
    return [
      _Section(title: 'Data', children: [
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
          leading: const Icon(Icons.delete_forever_outlined),
          title: Text('Reset all data',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () async {
            final ok = await confirmDelete(
              context,
              title: 'Reset all data?',
              message: 'This deletes all subjects, topics, and review history '
                  'on this device. Your backup file is left untouched.',
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
      ]),
    ];
  }

  List<Widget> _aboutSection() {
    return [
      _Section(title: 'About', children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Center(child: AppLogo(size: 132, elevated: false)),
        ),
        ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('RecallDay'),
          subtitle: Text('Remember today. Master tomorrow.'),
        ),
        ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('Your data stays on this device'),
          subtitle: Text(
            'No accounts. No cloud sync. No analytics. Backups are written to '
            'your own phone storage — nothing is uploaded anywhere.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
          ),
        ),
      ]),
    ];
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700,
                color: AppTheme.textMuted, letterSpacing: 0.6)),
      ),
      ...children,
    ]);
  }
}
