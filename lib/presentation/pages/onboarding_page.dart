import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/backup_service.dart';
import '../../services/notification_service.dart';
import '../../services/saf_service.dart';
import '../../services/storage_service.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/app_logo.dart';
import '../widgets/import_source.dart';

/// First-run setup.
///
/// Order matters for existing users: the backup is imported FIRST, and only
/// then is a folder nominated. The reverse order destroyed data. Picking the
/// folder used to prove it was writable by writing the real backup file, and
/// on a fresh install that meant writing an EMPTY database over the user's
/// own backup sitting in that folder — before they ever reached the import
/// step. By the time they selected their .zip, it held nothing.
///
/// Three rules now hold:
///   • Writability is proved with a throwaway probe file, never a real one.
///   • Nothing is written to the folder until the database is settled.
///   • Adopting a folder that already contains a backup renames it aside
///     rather than overwriting it.
///
/// The folder itself stays mandatory in both branches: without one everything
/// lives in app-private storage and an uninstall takes the lot.
enum _Step { welcome, newUser, existingImport, existingFolder }

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  _Step _step = _Step.welcome;
  bool _busy = false;

  String? _folderName;
  bool _folderReady = false;
  String? _restoredSummary;

  void _go(_Step s) {
    HapticFeedback.selectionClick();
    setState(() => _step = s);
  }

  Future<void> _details(String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  /// Pick a folder and prove we can actually write to it.
  ///
  /// The check writes a throwaway probe file and deletes it. It must not write
  /// the real backup: on a fresh install that would put an empty database over
  /// whatever the user already had in that folder.
  Future<void> _chooseFolder() async {
    final uri = await SafService.instance.pickFolder();
    if (uri == null || !mounted) return;

    setState(() => _busy = true);
    final writable = await SafService.instance.verifyWritable();
    final name = await SafService.instance.folderName();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _folderReady = writable;
      _folderName = name;
    });

    if (!writable) {
      await _details(
        'That folder can’t be used',
        'RecallDay could not write to it. Please choose another — a folder on '
        'your phone’s internal storage, such as Documents or Download, works '
        'best. Some cloud apps only offer read-only folders.',
      );
    }
  }

  Future<void> _importBackup() async {
    final source = await chooseImportSource(context);
    if (source == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final summary = source == ImportSource.folder
          ? await BackupService.instance.importFromFolder(merge: true)
          : await BackupService.instance.importArchive(merge: true);
      if (!mounted) return;
      if (summary.isEmpty) {
        await _details(
          'Nothing was restored',
          'That backup was read but held nothing to restore. Pick the '
          'file you exported, or the folder you unpacked it into.',
        );
      } else {
        setState(() => _restoredSummary = summary.toString());
      }
    } on BackupCancelled {
      // Picker dismissed; nothing to report.
    } catch (e) {
      if (mounted) await _details('That backup could not be read', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);

    // Ask for notification access here rather than on the splash screen.
    // Reminders are the whole point of the app, and the request lands better
    // once the user has chosen to set it up than as the first thing they see.
    await NotificationService.instance.requestPermissions();

    await StorageService.instance.markOnboarded();

    // Fold anything already in the folder into what we have, then write the
    // one canonical file. Previous and current data end up merged in a single
    // backup rather than sitting beside each other as rival copies.
    await BackupService.instance.adoptFolder();

    // Restored data carries no OS alarms, and a new install has none.
    await ref.read(topicCommandsProvider).reArmAllNotifications();
    if (!mounted) return;
    context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AppMotion.base,
          child: switch (_step) {
            _Step.welcome => _welcome(),
            _Step.newUser => _newUser(),
            _Step.existingFolder => _existingFolder(),
            _Step.existingImport => _existingImport(),
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- welcome

  Widget _welcome() {
    final tt = Theme.of(context).textTheme;
    return Padding(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const AppLogo(size: 168),
          const SizedBox(height: AppSpacing.xxl),
          Text('Welcome', style: tt.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Study something once, and RecallDay reminds you to revisit it '
            'just before you would forget.',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(height: 1.55),
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
            ),
            onPressed: () => _go(_Step.newUser),
            child: const Text('I’m new here'),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
            ),
            onPressed: () => _go(_Step.existingImport),
            child: const Text('I already use RecallDay'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Choose the second option if you have a backup file from a '
            'previous install.',
            textAlign: TextAlign.center,
            style: tt.labelSmall,
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- new user

  Widget _newUser() {
    return _StepScaffold(
      key: const ValueKey('newUser'),
      icon: Icons.folder_special_outlined,
      title: 'Choose where your data lives',
      body: 'RecallDay keeps a copy of everything in a folder you pick, and '
          'updates it as you go. That copy stays on your phone even if the app '
          'is uninstalled, so nothing is ever lost.\n\n'
          'A folder on internal storage — Documents, for example — works best.',
      onBack: () => _go(_Step.welcome),
      children: [
        _FolderTile(
          ready: _folderReady,
          name: _folderName,
          busy: _busy,
          onTap: _chooseFolder,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
          ),
          // Mandatory: the button stays disabled until a writable folder is set.
          onPressed: _folderReady && !_busy ? _finish : null,
          child: const Text('Start using RecallDay'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- existing user

  // ---------------------------------------------------------- existing user
  //
  // Import first, folder second. Doing it the other way round meant the folder
  // step wrote to the folder before any data existed, wiping the very backup
  // the next step was about to read.

  Widget _existingImport() {
    final tt = Theme.of(context).textTheme;
    final success = StatusColors.success(context);
    final done = _restoredSummary != null;

    return _StepScaffold(
      key: const ValueKey('existingImport'),
      icon: Icons.file_open_outlined,
      title: 'Bring your data back',
      body: 'Point RecallDay at the backup you saved — either the file you '
          'exported, or the folder you unpacked it into.\n\n'
          'Choosing the folder also brings your attachments across; a lone '
          'data file can only carry the records.\n\n'
          'It is only read, never changed. Your original file stays exactly '
          'where it is.',
      onBack: () => _go(_Step.welcome),
      children: [
        AppCard(
          onTap: _busy ? null : _importBackup,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.upload_file_outlined,
                color: done ? success : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? 'Backup loaded' : 'Select your backup',
                      style: tt.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done
                          ? _restoredSummary!
                          : 'Required — tap to choose a file or folder',
                      style: tt.labelSmall,
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
          ),
          onPressed:
              done && !_busy ? () => _go(_Step.existingFolder) : null,
          child: const Text('Next'),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Without this, someone who came down this path with no backup would
        // be stranded on a button that can never enable.
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() => _restoredSummary = null);
                  _go(_Step.newUser);
                },
          child: const Text('I don’t have my backup — start fresh'),
        ),
      ],
    );
  }

  Widget _existingFolder() {
    return _StepScaffold(
      key: const ValueKey('existingFolder'),
      icon: Icons.folder_special_outlined,
      title: 'Where should your data live?',
      body: 'Pick the folder RecallDay will keep your data in from now on, '
          'updating it as you go.\n\n'
          'It does not have to be the folder your backup came from — that is '
          'only a convenient option if you want everything in one place.\n\n'
          'RecallDay keeps a single backup file there and updates it in place. '
          'If the folder already has one, it is merged with what you just '
          'imported, so you never end up choosing between copies.',
      onBack: () => _go(_Step.existingImport),
      children: [
        _FolderTile(
          ready: _folderReady,
          name: _folderName,
          busy: _busy,
          onTap: _chooseFolder,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
          ),
          onPressed: _folderReady && !_busy ? _finish : null,
          child: const Text('Start using RecallDay'),
        ),
      ],
    );
  }
}

/// Shared layout for the steps after the welcome screen.
class _StepScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onBack;
  final List<Widget> children;

  const _StepScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onBack,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, 0, 0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.md,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(icon, color: cs.primary, size: 27),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(title, style: tt.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              Text(body, style: tt.bodySmall?.copyWith(height: 1.6)),
              const SizedBox(height: AppSpacing.xxl),
              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final bool ready;
  final String? name;
  final bool busy;
  final VoidCallback onTap;

  const _FolderTile({
    required this.ready,
    required this.name,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final success = StatusColors.success(context);

    return AppCard(
      onTap: busy ? null : onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.drive_folder_upload_outlined,
            color: ready ? success : cs.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? (name ?? 'Folder selected') : 'Choose folder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  ready
                      ? 'Your data is being saved here'
                      : 'Required — tap to pick one',
                  style: tt.labelSmall,
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}
