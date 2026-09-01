import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/subtopic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/attachment_editor.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/motion.dart';
import '../widgets/revise_action.dart';

/// One subtopic: its notes, its attachments, and the button that records a
/// revision. The leaf of Subject → Topic → Subtopic, and the only screen in
/// the app that changes a schedule.
class SubtopicDetailPage extends ConsumerStatefulWidget {
  final String subtopicId;
  const SubtopicDetailPage({super.key, required this.subtopicId});

  @override
  ConsumerState<SubtopicDetailPage> createState() =>
      _SubtopicDetailPageState();
}

class _SubtopicDetailPageState extends ConsumerState<SubtopicDetailPage> {
  @override
  void initState() {
    super.initState();
    // If launched from a notification action, replay it once Riverpod is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final action = GoRouterState.of(context).uri.queryParameters['action'];
      if (action == null || action.isEmpty) return;
      final cmd = ref.read(topicCommandsProvider);
      switch (action) {
        case 'mark_done':
          cmd.reviewSubtopic(widget.subtopicId, ReviewRating.good);
          break;
        case 'snooze':
          cmd.snoozeSubtopic(widget.subtopicId, const Duration(hours: 1));
          break;
        case 'skip':
          cmd.snoozeSubtopic(widget.subtopicId, const Duration(days: 1));
          break;
      }
    });
  }

  void _leave() {
    // Opened from a notification this page is the whole stack, so pop() would
    // strand the user on "Subtopic not found".
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/today');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final subtopics = ref.watch(subtopicsStreamProvider).valueOrNull ?? const [];
    final subtopic =
        subtopics.where((s) => s.id == widget.subtopicId).firstOrNull;

    if (subtopic == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Subtopic not found', style: tt.bodyMedium)),
      );
    }

    final subject = ref.watch(subjectsByIdProvider)[subtopic.subjectId];
    final topic = ref.watch(topicsByIdProvider)[subtopic.topicId];
    final accent = SubjectPalette.readable(
      subject?.color ?? cs.primary,
      theme.brightness,
    );
    final paused = subtopic.status == SubtopicStatus.paused;
    final notes = subtopic.notes?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(topic?.title ?? subject?.name ?? 'Subtopic',
            style: tt.titleMedium),
        actions: [
          // Three icon buttons crowded the bar and gave delete the same weight
          // as edit. Secondary actions now live in an overflow menu.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  context.push('/edit/subtopic/${subtopic.id}');
                case 'pause':
                  HapticFeedback.selectionClick();
                  await ref.read(topicCommandsProvider).setStatus(
                        subtopic.id,
                        paused
                            ? SubtopicStatus.active
                            : SubtopicStatus.paused,
                      );
                case 'delete':
                  final ok = await confirmDelete(
                    context,
                    title: 'Delete subtopic?',
                    message: 'This permanently removes “${subtopic.title}” '
                        'and its review history.',
                  );
                  if (!ok || !mounted) return;
                  await ref
                      .read(topicCommandsProvider)
                      .deleteSubtopic(subtopic.id);
                  if (mounted) _leave();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem(
                value: 'pause',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  title: Text(paused ? 'Resume reminders' : 'Pause reminders'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: cs.error,
                  ),
                  title: Text('Delete', style: TextStyle(color: cs.error)),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.xxxl,
          ),
          children: [
            FadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Both ancestors, both tappable — this page is reachable
                  // straight from a notification, where it is otherwise the
                  // entire navigation stack.
                  _Breadcrumb(
                    subjectName: subject?.name,
                    topicName: topic?.title,
                    accent: accent,
                    onSubject: subject == null
                        ? null
                        : () => context.push('/subject/${subject.id}'),
                    onTopic: topic == null
                        ? null
                        : () => context.push('/topic/${topic.id}'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(subtopic.title, style: tt.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      AppPill(
                        paused
                            ? 'Paused'
                            : '${DateLabels.relative(subtopic.nextDueAt)}'
                                ' · ${DateLabels.time(subtopic.nextDueAt)}',
                        icon: paused
                            ? Icons.pause_circle_outline_rounded
                            : Icons.event_rounded,
                        color: subtopic.isOverdue ? cs.error : cs.primary,
                        tonal: true,
                      ),
                      AppPill(
                        '${subtopic.repetitions} review'
                        '${subtopic.repetitions == 1 ? '' : 's'}',
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                index: 1,
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: MarkdownBody(
                    data: notes,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: tt.bodyMedium?.copyWith(height: 1.6),
                      code: tt.bodySmall?.copyWith(
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            FadeSlideIn(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attachments', style: tt.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  AttachmentEditor(
                    subtopicId: subtopic.id,
                    attachments: subtopic.attachments,
                    onChanged: (v) => ref
                        .read(topicCommandsProvider)
                        .setAttachments(subtopic.id, v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FadeSlideIn(
              index: 3,
              child: subtopic.status == SubtopicStatus.completed
                  ? _MasteredPanel(subtopic: subtopic)
                  : _ReviewPanel(subtopic: subtopic),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Subject › Topic", each half tappable.
class _Breadcrumb extends StatelessWidget {
  final String? subjectName;
  final String? topicName;
  final Color accent;
  final VoidCallback? onSubject;
  final VoidCallback? onTopic;

  const _Breadcrumb({
    required this.subjectName,
    required this.topicName,
    required this.accent,
    this.onSubject,
    this.onTopic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    if (subjectName == null && topicName == null) return const SizedBox.shrink();

    Widget crumb(String text, Color color, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (subjectName != null)
          Flexible(child: crumb(subjectName!, accent, onSubject)),
        if (subjectName != null && topicName != null)
          Icon(
            Icons.chevron_right_rounded,
            size: 15,
            color: cs.onSurfaceVariant,
          ),
        if (topicName != null)
          Flexible(child: crumb(topicName!, cs.onSurfaceVariant, onTopic)),
      ],
    );
  }
}

/// The revision control.
///
/// One button, not a four-way rating. The Forgot/Hard/Good/Easy grades were
/// removed at the user's request: they asked to be shown once whether they had
/// revised something, not to grade the quality of every recall. Every revision
/// now records the same neutral result, so the interval still lengthens on the
/// usual ladder without asking the user to self-score.
class _ReviewPanel extends ConsumerWidget {
  final Subtopic subtopic;
  const _ReviewPanel({required this.subtopic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    // Day-granular, so this appears at midnight along with the Today listing
    // rather than at the reminder hour. See Subtopic.isDue.
    final due = subtopic.isDue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(due ? 'Ready to revise?' : 'Next revision', style: tt.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          due
              ? 'Mark it done once you have been through the material.'
              : 'This is not due yet — it will appear on your home screen '
                  'on ${DateLabels.relative(subtopic.nextDueAt)}.',
          style: tt.labelSmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Only offered while it is actually due. Once revised its next due
        // date moves forward, so the button disappears and a subtopic can't be
        // revised twice for the same date.
        if (due)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
            ),
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('Revised'),
            onPressed: () async {
              await reviseSubtopic(
                context,
                ref,
                subtopic.id,
                subtopic.title,
              );
            },
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  size: 19,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${DateLabels.relative(subtopic.nextDueAt)} at '
                    '${DateLabels.time(subtopic.nextDueAt)}',
                    style: tt.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: AppSpacing.xxl),
        Divider(color: cs.outlineVariant),
        const SizedBox(height: AppSpacing.lg),

        // The "I know this now" exit. One clear, full-width control rather
        // than an option buried in the overflow menu, because deciding you've
        // mastered something is a deliberate, first-class action.
        Text('Confident with this?', style: tt.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Stop the spaced repetition and no further reminders will be sent. '
          'You can restart it any time.',
          style: tt.labelSmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            foregroundColor: cs.primary,
          ),
          icon: const Icon(Icons.task_alt_rounded, size: 20),
          label: const Text('Stop repetition — I know this'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Stop reminders for this subtopic?'),
                content: Text(
                  '“${subtopic.title}” will be marked as mastered and '
                  'RecallDay will stop reminding you about it. It stays in '
                  'its topic, and you can restart repetition whenever you '
                  'like.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Stop reminders'),
                  ),
                ],
              ),
            );
            if (ok != true) return;
            HapticFeedback.mediumImpact();
            await ref.read(topicCommandsProvider).stopRepetition(subtopic.id);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('Mastered · reminders stopped')),
              );
          },
        ),
      ],
    );
  }
}

/// Shown in place of the rating buttons once a subtopic has been mastered, so
/// the state is obvious and reversible rather than the screen looking empty.
class _MasteredPanel extends ConsumerWidget {
  final Subtopic subtopic;
  const _MasteredPanel({required this.subtopic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final success = StatusColors.success(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: success.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.task_alt_rounded, color: success, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Mastered',
                    style: tt.titleMedium?.copyWith(color: success),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Repetition is stopped, so no reminders will be sent for this '
                'subtopic. Your review history is kept.',
                style: tt.labelSmall?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          label: const Text('Start repetition again'),
          onPressed: () async {
            HapticFeedback.lightImpact();
            await ref
                .read(topicCommandsProvider)
                .resumeRepetition(subtopic.id);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('Back in your schedule')),
              );
          },
        ),
      ],
    );
  }
}
