import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/attachment_editor.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/motion.dart';
import '../widgets/revise_action.dart';

class TopicDetailPage extends ConsumerStatefulWidget {
  final String topicId;
  const TopicDetailPage({super.key, required this.topicId});

  @override
  ConsumerState<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends ConsumerState<TopicDetailPage> {
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
          cmd.reviewTopic(widget.topicId, ReviewRating.good);
          break;
        case 'snooze':
          cmd.snoozeTopic(widget.topicId, const Duration(hours: 1));
          break;
        case 'skip':
          cmd.snoozeTopic(widget.topicId, const Duration(days: 1));
          break;
      }
    });
  }

  void _leave() {
    // Opened from a notification this page is the whole stack, so pop() would
    // strand the user on "Topic not found".
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

    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final topic = topics.where((t) => t.id == widget.topicId).firstOrNull;
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    if (topic == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Topic not found', style: tt.bodyMedium)),
      );
    }

    final subject = subjects.where((s) => s.id == topic.subjectId).firstOrNull;
    final accent = SubjectPalette.readable(
      subject?.color ?? cs.primary,
      theme.brightness,
    );
    final paused = topic.status == TopicStatus.paused;
    final notes = topic.notes?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(subject?.name ?? 'Topic', style: tt.titleMedium),
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
                  context.push('/edit/topic/${topic.id}');
                case 'pause':
                  HapticFeedback.selectionClick();
                  await ref.read(topicCommandsProvider).setStatus(
                        topic.id,
                        paused ? TopicStatus.active : TopicStatus.paused,
                      );
                case 'delete':
                  final ok = await confirmDelete(
                    context,
                    title: 'Delete topic?',
                    message: 'This permanently removes “${topic.title}” '
                        'and its review history.',
                  );
                  if (!ok || !mounted) return;
                  await ref
                      .read(topicCommandsProvider)
                      .deleteTopic(topic.id);
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
                  if (subject != null)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          subject.name,
                          style: tt.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(topic.title, style: tt.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      AppPill(
                        paused
                            ? 'Paused'
                            : '${DateLabels.relative(topic.nextDueAt)}'
                                ' · ${DateLabels.time(topic.nextDueAt)}',
                        icon: paused
                            ? Icons.pause_circle_outline_rounded
                            : Icons.event_rounded,
                        color: topic.isOverdue ? cs.error : cs.primary,
                        tonal: true,
                      ),
                      AppPill(
                        '${topic.repetitions} review'
                        '${topic.repetitions == 1 ? '' : 's'}',
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
                    topicId: topic.id,
                    attachments: topic.attachments,
                    onChanged: (v) => ref
                        .read(topicCommandsProvider)
                        .setAttachments(topic.id, v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FadeSlideIn(
              index: 3,
              child: topic.status == TopicStatus.completed
                  ? _MasteredPanel(topic: topic)
                  : _ReviewPanel(topic: topic),
            ),
          ],
        ),
      ),
    );
  }
}

/// The revision control.
///
/// One button, not a four-way rating. The Forgot/Hard/Good/Easy grades were
/// removed at the user's request: they asked to be shown once whether they had
/// revised a topic, not to grade the quality of every recall. Every revision
/// now records the same neutral result, so the interval still lengthens on the
/// usual ladder without asking the user to self-score.
class _ReviewPanel extends ConsumerWidget {
  final Topic topic;
  const _ReviewPanel({required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final due = topic.isDue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(due ? 'Ready to revise?' : 'Next revision', style: tt.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          due
              ? 'Mark it done once you have been through the material.'
              : 'This topic is not due yet — it will appear on your home '
                  'screen on ${DateLabels.relative(topic.nextDueAt)}.',
          style: tt.labelSmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Only offered while the topic is actually due. Once revised its next
        // due date moves forward, so the button disappears and a topic can't
        // be revised twice for the same date.
        if (due)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
            ),
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('Revised'),
            onPressed: () async {
              await reviseTopic(context, ref, topic.id, topic.title);
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
                    '${DateLabels.relative(topic.nextDueAt)} at '
                    '${DateLabels.time(topic.nextDueAt)}',
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
        Text('Confident with this topic?', style: tt.titleMedium),
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
                title: const Text('Stop reminders for this topic?'),
                content: Text(
                  '“${topic.title}” will be marked as mastered and RecallDay '
                  'will stop reminding you about it. It stays in your subject, '
                  'and you can restart repetition whenever you like.',
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
            await ref.read(topicCommandsProvider).stopRepetition(topic.id);
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

/// Shown in place of the rating buttons once a topic has been mastered, so the
/// state is obvious and reversible rather than the screen just looking empty.
class _MasteredPanel extends ConsumerWidget {
  final Topic topic;
  const _MasteredPanel({required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final success = theme.brightness == Brightness.light
        ? StatusColors.successLight
        : StatusColors.successDark;

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
                'topic. Your review history is kept.',
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
            await ref.read(topicCommandsProvider).resumeRepetition(topic.id);
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
