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
import '../widgets/delete_confirm.dart';
import '../widgets/motion.dart';

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
                      AppPill(
                        '${topic.estimatedMinutes} min',
                        icon: Icons.timer_outlined,
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
              child: _ReviewPanel(topic: topic),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rating control.
///
/// Each button previews the interval it would schedule — the engine can tell us
/// exactly, and seeing "Good · 7d" before committing makes the spacing system
/// legible instead of opaque.
class _ReviewPanel extends ConsumerWidget {
  final Topic topic;
  const _ReviewPanel({required this.topic});

  static const _labels = ['Forgot', 'Hard', 'Good', 'Easy'];
  static const _ratings = [
    ReviewRating.forgot,
    ReviewRating.hard,
    ReviewRating.good,
    ReviewRating.easy,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final colors = StatusColors.ratings(theme.brightness);
    final engine = ref.read(engineProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How well did you remember?', style: tt.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your answer sets the next reminder.',
          style: tt.labelSmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              Expanded(
                child: _RatingButton(
                  label: _labels[i],
                  interval: _fmt(
                    engine.schedule(topic, _ratings[i]).nextIntervalDays,
                  ),
                  color: colors[i],
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await ref
                        .read(topicCommandsProvider)
                        .reviewTopic(topic.id, _ratings[i]);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            'Saved · next in ${_fmt(engine.schedule(topic, _ratings[i]).nextIntervalDays)}',
                          ),
                        ),
                      );
                  },
                ),
              ),
              if (i < 3) const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }

  static String _fmt(int days) {
    if (days <= 0) return 'today';
    if (days == 1) return '1 day';
    if (days < 30) return '$days days';
    if (days < 365) return '${(days / 30).round()} mo';
    return '${(days / 365).round()} yr';
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final String interval;
  final Color color;
  final VoidCallback onTap;

  const _RatingButton({
    required this.label,
    required this.interval,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
          child: Column(
            children: [
              Text(
                label,
                style: tt.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                interval,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
