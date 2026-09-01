import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/subtopic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/empty_state.dart';
import '../widgets/motion.dart';
import '../widgets/revise_action.dart';
import '../widgets/subtopic_card.dart';

/// A topic, as a list of its subtopics.
///
/// Level three of Subject → Topic → Subtopic, and the first level where there
/// is something to do: the rows carry the same Done / Not done pair as the
/// Today screen, so a study session can run straight down a chapter without
/// bouncing back to the home tab between each one.
class TopicDetailPage extends ConsumerWidget {
  final String topicId;
  const TopicDetailPage({super.key, required this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final topic = ref.watch(topicsByIdProvider)[topicId];

    if (topic == null) {
      // A notification scheduled by an older build deep-links to
      // /topic/<leaf id>. The leaf ids never changed, so rather than showing
      // "not found" for a record that is right there, hand it to the page that
      // now owns it.
      final subtopics = ref.watch(subtopicsStreamProvider).valueOrNull;
      if (subtopics != null && subtopics.any((s) => s.id == topicId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.pushReplacement('/subtopic/$topicId');
        });
        return const Scaffold(body: SizedBox.shrink());
      }
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Topic not found', style: tt.bodyMedium)),
      );
    }

    final subject = ref.watch(subjectsByIdProvider)[topic.subjectId];
    final subtopics = ref.watch(subtopicsForTopicProvider(topicId));
    final accent = SubjectPalette.readable(
      subject?.color ?? cs.primary,
      theme.brightness,
    );

    final due = subtopics.where((s) => s.isDue).length;
    final mastered = subtopics
        .where((s) => s.status == SubtopicStatus.completed)
        .length;
    final success = StatusColors.success(context);

    Future<void> confirmAndDelete() async {
      final ok = await confirmDelete(
        context,
        title: 'Delete topic?',
        message: subtopics.isEmpty
            ? 'This permanently removes “${topic.title}”.'
            : 'This permanently removes “${topic.title}” and the '
                '${subtopics.length} subtopic'
                '${subtopics.length == 1 ? '' : 's'} inside it, including all '
                'review history.',
      );
      if (!ok || !context.mounted) return;
      await ref.read(topicCommandsProvider).deleteTopicCascading(topicId);
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/subjects');
      }
    }

    final newSubtopicPath =
        '/create/subtopic?subjectId=${topic.subjectId}&topicId=$topicId';

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
              title: Text(topic.title, style: tt.titleMedium),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  onSelected: (v) {
                    if (v == 'edit') {
                      context.push('/edit/topic/$topicId');
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
                        title: Text('Edit topic'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            Icon(Icons.delete_outline_rounded, color: cs.error),
                        title: Text(
                          'Delete topic',
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The subject line is a link, not decoration: it is the
                        // only way back up a level when this page was opened
                        // from Today rather than by drilling down.
                        if (subject != null)
                          InkWell(
                            onTap: () =>
                                context.push('/subject/${subject.id}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    SubjectPalette.iconFor(subject.iconKey),
                                    size: 15,
                                    color: accent,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      subject.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.labelSmall?.copyWith(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
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
                                color: StatusColors.warning(context),
                                tonal: true,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            if (mastered > 0)
                              AppPill(
                                '$mastered mastered',
                                color: success,
                                tonal: true,
                              ),
                            if (due == 0 && mastered == 0)
                              Text('Nothing due', style: tt.labelSmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (subtopics.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.note_add_outlined,
                  title: 'No subtopics here yet',
                  subtitle:
                      'Subtopics are what RecallDay actually schedules. Add '
                      'one to “${topic.title}” and the revisions start.',
                  action: FilledButton.icon(
                    onPressed: () => context.push(newSubtopicPath),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add subtopic'),
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Subtopics',
                  count: subtopics.length,
                  accent: accent,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                sliver: SliverList.separated(
                  itemCount: subtopics.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final s = subtopics[i];
                    final actionable = s.isDue;
                    return FadeSlideIn(
                      index: i,
                      child: SwipeToDelete(
                        itemKey: ValueKey('subtopic-${s.id}'),
                        title: 'Delete subtopic?',
                        message: 'This permanently removes “${s.title}” '
                            'and its review history.',
                        onDelete: () => ref
                            .read(topicCommandsProvider)
                            .deleteSubtopic(s.id),
                        child: SubtopicCard(
                          subtopic: s,
                          topicName: topic.title,
                          subjectName: subject?.name ?? 'No subject',
                          accent: subject?.color ?? cs.primary,
                          relativeLabel: DateLabels.relative(s.nextDueAt),
                          onTap: () => context.push('/subtopic/${s.id}'),
                          onDone: actionable
                              ? () =>
                                  reviseSubtopic(context, ref, s.id, s.title)
                              : null,
                          onMissed: actionable
                              ? () => markMissed(context, ref, s.id, s.title)
                              : null,
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
      floatingActionButton: subtopics.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(newSubtopicPath),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add subtopic'),
            ),
    );
  }
}
