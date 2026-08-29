import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/empty_state.dart';
import '../widgets/motion.dart';
import '../widgets/tab_app_bar.dart';

/// Subjects.
///
/// Switched from a 2-up square grid to a single-column list. The grid forced
/// every name to one ellipsised line and left a lot of dead space in each
/// tile; a list row fits the name, the counts and a progress hint comfortably,
/// and scans faster because everything is on one axis.
class SubjectsPage extends ConsumerWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            TabAppBar(
              title: 'Subjects',
              subtitle: subjects.isEmpty
                  ? null
                  : '${subjects.length} subject'
                      '${subjects.length == 1 ? '' : 's'} · '
                      '${topics.length} topic${topics.length == 1 ? '' : 's'}',
            ),
            if (subjects.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'No subjects yet',
                  subtitle:
                      'Subjects group your topics — Algorithms, Anatomy, '
                      'Spanish. Create one to get started.',
                  action: FilledButton.icon(
                    onPressed: () => context.push('/create/subject'),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('New subject'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.xs,
                  AppSpacing.gutter,
                  AppSpacing.bottomInset,
                ),
                sliver: SliverList.separated(
                  itemCount: subjects.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final s = subjects[i];
                    final mine =
                        topics.where((t) => t.subjectId == s.id).toList();
                    final due = mine.where((t) => t.isDue).length;
                    return FadeSlideIn(
                      index: i,
                      child: _SubjectRow(
                        name: s.name,
                        color: s.color,
                        iconKey: s.iconKey,
                        total: mine.length,
                        due: due,
                        onTap: () => context.push('/subject/${s.id}'),
                        onLongPress: () => _showActions(
                          context,
                          ref,
                          s.id,
                          s.name,
                          mine.length,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        Positioned(
          right: AppSpacing.gutter,
          bottom: AppSpacing.gutter,
          child: FloatingActionButton.extended(
            onPressed: () => context.push('/create/subject'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New subject'),
          ),
        ),
      ],
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    String subjectId,
    String name,
    int topicCount,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.sm,
                  AppSpacing.gutter,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: tt.titleMedium),
                          Text(
                            '$topicCount topic${topicCount == 1 ? '' : 's'}',
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit subject'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Delete subject',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
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

class _SubjectRow extends StatelessWidget {
  final String name;
  final Color color;
  final String iconKey;
  final int total;
  final int due;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SubjectRow({
    required this.name,
    required this.color,
    required this.iconKey,
    required this.total,
    required this.due,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final c = SubjectPalette.readable(color, theme.brightness);

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(SubjectPalette.iconFor(iconKey), color: c, size: 21),
          ),
          const SizedBox(width: AppSpacing.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  total == 0
                      ? 'No topics yet'
                      : '$total topic${total == 1 ? '' : 's'}',
                  style: tt.labelSmall,
                ),
              ],
            ),
          ),
          if (due > 0) ...[
            AppPill('$due due', color: c, tonal: true),
            const SizedBox(width: AppSpacing.sm),
          ],
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}
