import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/subtopic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/empty_state.dart';
import '../widgets/motion.dart';
import '../widgets/topic_card.dart';

/// A subject, as a list of its topics.
///
/// Level two of Subject → Topic → Subtopic. Nothing here is schedulable, so
/// there are no revision buttons: the row counts tell you where the work is
/// and you drill into a topic to do it.
class SubjectDetailPage extends ConsumerWidget {
  final String subjectId;
  const SubjectDetailPage({super.key, required this.subjectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final subject = ref.watch(subjectsByIdProvider)[subjectId];
    final topics = ref.watch(topicsForSubjectProvider(subjectId));
    final subtopics = ref.watch(subtopicsForSubjectProvider(subjectId));

    if (subject == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Subject not found', style: tt.bodyMedium)),
      );
    }

    final accent = SubjectPalette.readable(subject.color, theme.brightness);
    final due = subtopics.where((s) => s.isDue).length;
    final done = subtopics
        .where((s) => s.status == SubtopicStatus.completed)
        .length;
    final success = StatusColors.success(context);

    // Grouped once rather than filtered per row: a subject with a lot of
    // topics would otherwise walk the whole subtopic list for every card.
    final byTopic = <String, List<Subtopic>>{};
    for (final s in subtopics) {
      byTopic.putIfAbsent(s.topicId, () => <Subtopic>[]).add(s);
    }

    Future<void> confirmAndDelete() async {
      final ok = await confirmDelete(
        context,
        title: 'Delete subject?',
        message: topics.isEmpty
            ? 'This permanently removes “${subject.name}”.'
            : 'This permanently removes “${subject.name}”, its '
                '${topics.length} topic${topics.length == 1 ? '' : 's'} and '
                'the ${subtopics.length} subtopic'
                '${subtopics.length == 1 ? '' : 's'} inside them, including '
                'all review history.',
      );
      if (!ok || !context.mounted) return;
      await ref.read(topicCommandsProvider).deleteSubjectCascading(subjectId);
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/subjects');
      }
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: theme.scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              title: Text(subject.name, style: tt.titleMedium),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') {
                      context.push('/edit/subject/$subjectId');
                    } else {
                      confirmAndDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit subject'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            Icon(Icons.delete_outline_rounded, color: cs.error),
                        title: Text(
                          'Delete subject',
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.xs,
                  AppSpacing.gutter,
                  0,
                ),
                child: FadeSlideIn(
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            SubjectPalette.iconFor(subject.iconKey),
                            color: accent,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${topics.length} topic'
                                '${topics.length == 1 ? '' : 's'} · '
                                '${subtopics.length} subtopic'
                                '${subtopics.length == 1 ? '' : 's'}',
                                style: tt.titleMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  if (due > 0) ...[
                                    AppPill(
                                      '$due due',
                                      color: cs.primary,
                                      tonal: true,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                  ],
                                  if (done > 0)
                                    AppPill(
                                      '$done done',
                                      color: success,
                                      tonal: true,
                                    ),
                                  if (due == 0 && done == 0)
                                    Text('Nothing due', style: tt.labelSmall),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (topics.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.topic_outlined,
                  title: 'No topics here yet',
                  subtitle:
                      'Topics divide “${subject.name}” into chapters. Add one, '
                      'then put the subtopics you actually revise inside it.',
                  action: FilledButton.icon(
                    onPressed: () =>
                        context.push('/create/topic?subjectId=$subjectId'),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add topic'),
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Topics',
                  count: topics.length,
                  accent: accent,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                sliver: SliverList.separated(
                  itemCount: topics.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final t = topics[i];
                    final mine = byTopic[t.id] ?? const <Subtopic>[];
                    return FadeSlideIn(
                      index: i,
                      child: SwipeToDelete(
                        itemKey: ValueKey('topic-${t.id}'),
                        title: 'Delete topic?',
                        message: mine.isEmpty
                            ? 'This permanently removes “${t.title}”.'
                            : 'This permanently removes “${t.title}” and the '
                                '${mine.length} subtopic'
                                '${mine.length == 1 ? '' : 's'} inside it, '
                                'including all review history.',
                        onDelete: () => ref
                            .read(topicCommandsProvider)
                            .deleteTopicCascading(t.id),
                        child: TopicCard(
                          title: t.title,
                          accent: subject.color,
                          subtopicCount: mine.length,
                          dueCount: mine.where((s) => s.isDue).length,
                          masteredCount: mine
                              .where((s) =>
                                  s.status == SubtopicStatus.completed)
                              .length,
                          onTap: () => context.push('/topic/${t.id}'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SliverPadding(
              padding: EdgeInsets.only(bottom: AppSpacing.bottomInset),
            ),
          ],
        ),
      ),
      floatingActionButton: topics.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  context.push('/create/topic?subjectId=$subjectId'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add topic'),
            ),
    );
  }
}
