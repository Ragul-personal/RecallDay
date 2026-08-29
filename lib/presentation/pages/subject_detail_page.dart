import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/empty_state.dart';
import '../widgets/topic_card.dart';

class SubjectDetailPage extends ConsumerWidget {
  final String subjectId;
  const SubjectDetailPage({super.key, required this.subjectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final subject = subjects.where((s) => s.id == subjectId).firstOrNull;
    final allTopics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final topics = allTopics.where((t) => t.subjectId == subjectId).toList()
      ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));

    if (subject == null) {
      return const Scaffold(body: Center(child: Text('Subject not found')));
    }

    Future<void> confirmAndDelete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete subject?'),
          content: Text(
            topics.isEmpty
                ? 'This permanently removes the subject.'
                : 'This permanently removes the subject and its '
                    '${topics.length} topic${topics.length == 1 ? '' : 's'}, '
                    'including all review history.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await ref
          .read(topicCommandsProvider)
          .deleteSubjectCascading(subjectId);
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/subjects');
      }
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(subject.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit subject',
                onPressed: () => context.push('/edit/subject/$subjectId'),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete subject',
                onPressed: confirmAndDelete,
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add topic',
                onPressed: () =>
                    context.push('/create/topic?subjectId=$subjectId'),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outline, width: 0.6),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: subject.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(SubjectPalette.iconFor(subject.iconKey),
                        color: subject.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${topics.length} topics',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(
                          '${topics.where((t) => t.isDue).length} due · '
                          '${topics.where((t) => t.status == TopicStatus.completed).length} completed',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
          if (topics.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.note_add_outlined,
                title: 'No topics in this subject',
                subtitle: 'Add a topic to start a revision schedule.',
              ),
            )
          else
            SliverList.separated(
              itemCount: topics.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = topics[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SwipeToDelete(
                    itemKey: ValueKey('topic-${t.id}'),
                    title: 'Delete topic?',
                    message: 'This permanently removes “${t.title}” '
                        'and its review history.',
                    onDelete: () =>
                        ref.read(topicCommandsProvider).deleteTopic(t.id),
                    child: TopicCard(
                      topic: t,
                      subjectName: subject.name,
                      accent: subject.color,
                      relativeLabel: DateLabels.relative(t.nextDueAt),
                      onTap: () => context.push('/topic/${t.id}'),
                    ),
                  ),
                );
              },
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ]),
      ),
    );
  }
}
