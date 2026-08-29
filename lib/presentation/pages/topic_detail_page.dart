import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';

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
          // Skip = reschedule to tomorrow without recording a review.
          cmd.snoozeTopic(widget.topicId, const Duration(days: 1));
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final topic = topics.where((t) => t.id == widget.topicId).firstOrNull;
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    if (topic == null) {
      return const Scaffold(body: Center(child: Text('Topic not found')));
    }
    final subject = subjects.where((s) => s.id == topic.subjectId).firstOrNull;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(subject?.name ?? 'Topic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit topic',
            onPressed: () => context.push('/edit/topic/${topic.id}'),
          ),
          IconButton(
            icon: Icon(topic.status == TopicStatus.paused
                ? Icons.play_arrow
                : Icons.pause_outlined),
            tooltip: topic.status == TopicStatus.paused ? 'Resume' : 'Pause',
            onPressed: () {
              ref.read(topicCommandsProvider).setStatus(
                  topic.id,
                  topic.status == TopicStatus.paused
                      ? TopicStatus.active
                      : TopicStatus.paused);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete topic',
            onPressed: () async {
              // Note the dialog's OWN context (`ctx`) in the pop calls. Using
              // the page context happens to work while the dialog is the
              // topmost route, but breaks the moment this page is nested under
              // another navigator.
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete topic?'),
                  content: const Text(
                      'This permanently removes the topic and its review history.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(ctx).colorScheme.error),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok != true || !mounted) return;
              await ref.read(topicCommandsProvider).deleteTopic(topic.id);
              if (!mounted) return;
              // Opened from a notification, this page is the whole stack, so
              // pop() would leave the user staring at "Topic not found".
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/today');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(topic.title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _MetaPill('Next: ${DateLabels.relative(topic.nextDueAt)}, ${DateLabels.time(topic.nextDueAt)}'),
              _MetaPill('${topic.repetitions} reviews'),
              _MetaPill('ease ${topic.ease.toStringAsFixed(2)}'),
              _MetaPill('${topic.estimatedMinutes} min'),
              if (topic.lastReviewedAt != null)
                _MetaPill('last: ${DateLabels.relative(topic.lastReviewedAt!)}'),
            ]),
            if (topic.notes != null && topic.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outline, width: 0.6),
                ),
                child: MarkdownBody(data: topic.notes!),
              ),
            ],
            const SizedBox(height: 22),
            const Text('How well did you remember it?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _ReviewActions(topicId: topic.id),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String text;
  const _MetaPill(this.text);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
    );
  }
}

class _ReviewActions extends ConsumerWidget {
  final String topicId;
  const _ReviewActions({required this.topicId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cmd = ref.read(topicCommandsProvider);
    final colors = const [
      Color(0xFFEF8C8C), // forgot
      Color(0xFFE0A878), // hard
      Color(0xFF8FD9C0), // good
      Color(0xFF7C9CFF), // easy
    ];
    final labels = const ['Forgot', 'Hard', 'Good', 'Easy'];
    final ratings = const [
      ReviewRating.forgot, ReviewRating.hard, ReviewRating.good, ReviewRating.easy,
    ];
    return Row(children: [
      for (int i = 0; i < 4; i++) ...[
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors[i].withValues(alpha: 0.18),
              foregroundColor: colors[i],
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () async {
              await cmd.reviewTopic(topicId, ratings[i]);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved · marked ${labels[i].toLowerCase()}')),
                );
              }
            },
            child: Text(labels[i], style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        if (i < 3) const SizedBox(width: 8),
      ],
    ]);
  }
}
