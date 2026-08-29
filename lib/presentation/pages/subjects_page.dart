import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/empty_state.dart';

class SubjectsPage extends ConsumerWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];

    return Stack(children: [
      CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: const Text('Subjects'),
        ),
        if (subjects.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.bookmark_add_outlined,
              title: 'No subjects yet',
              subtitle: 'Group your topics into subjects like DBMS or Algorithms.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: subjects.length,
              itemBuilder: (_, i) {
                final s = subjects[i];
                final count = topics.where((t) => t.subjectId == s.id).length;
                final due = topics.where((t) =>
                    t.subjectId == s.id && t.isDue).length;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => context.push('/subject/${s.id}'),
                    // Long-press for edit/delete without having to open the
                    // subject first.
                    onLongPress: () => _showSubjectActions(
                        context, ref, s.id, s.name, count),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cs.outline, width: 0.6),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: s.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(SubjectPalette.iconFor(s.iconKey),
                                color: s.color, size: 20),
                          ),
                          const Spacer(),
                          Text(s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('$count topics · $due due',
                              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ).animate(delay: (40 * i).ms).fadeIn(duration: 250.ms);
              },
            ),
          ),
      ]),
      Positioned(
        right: 20, bottom: 20,
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/create/subject'),
          icon: const Icon(Icons.add),
          label: const Text('New subject'),
        ),
      ),
    ]);
  }

  Future<void> _showSubjectActions(
    BuildContext context,
    WidgetRef ref,
    String subjectId,
    String name,
    int topicCount,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('$topicCount topic${topicCount == 1 ? '' : 's'}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit subject'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('Delete subject',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    if (action == 'edit') {
      context.push('/edit/subject/$subjectId');
      return;
    }

    final ok = await confirmDelete(
      context,
      title: 'Delete subject?',
      message: topicCount == 0
          ? 'This permanently removes “$name”.'
          : 'This permanently removes “$name” and its $topicCount '
              'topic${topicCount == 1 ? '' : 's'}, including all review history.',
    );
    if (!ok) return;
    await ref.read(topicCommandsProvider).deleteSubjectCascading(subjectId);
  }
}
