import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/topic_card.dart';
import '../widgets/empty_state.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final due = ref.watch(dueTodayProvider);
    final overdue = ref.watch(overdueProvider);
    final upcoming = ref.watch(upcomingProvider);
    final streak = ref.watch(streakDaysProvider);
    final allReviews = ref.watch(topicRepositoryProvider).allReviews();
    final completedToday = allReviews.where((r) {
      final n = DateTime.now();
      return r.reviewedAt.year == n.year &&
          r.reviewedAt.month == n.month &&
          r.reviewedAt.day == n.day;
    }).length;

    return Stack(children: [
      CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          floating: false,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: const Text('Today'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                _StatCard(
                  label: 'Streak',
                  value: '$streak',
                  unit: streak == 1 ? 'day' : 'days',
                  accent: cs.primary,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Done today',
                  value: '$completedToday',
                  unit: 'reviewed',
                  accent: const Color(0xFF8FD9C0),
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Pending',
                  value: '${due.length}',
                  unit: 'today',
                  accent: const Color(0xFFE0A878),
                ),
              ],
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),
          ),
        ),
        if (overdue.isNotEmpty) ...[
          _SectionHeader(title: 'Overdue', count: overdue.length, color: cs.error),
          _TopicSliver(topics: overdue),
        ],
        if (due.isNotEmpty) ...[
          _SectionHeader(title: 'Due today', count: due.length),
          _TopicSliver(topics: due),
        ],
        if (upcoming.isNotEmpty) ...[
          _SectionHeader(title: 'Upcoming', count: upcoming.take(20).length),
          _TopicSliver(topics: upcoming.take(20).toList()),
        ],
        if (overdue.isEmpty && due.isEmpty && upcoming.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.weekend_outlined,
              title: 'Nothing on your plate',
              subtitle: 'Add a topic to start tracking your revisions.',
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
      ],
    ),
      Positioned(
        right: 20, bottom: 20,
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/create/topic'),
          icon: const Icon(Icons.add),
          label: const Text('New topic'),
        ),
      ),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, unit;
  final Color accent;
  const _StatCard({required this.label, required this.value, required this.unit, required this.accent});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w600, color: accent)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color? color;
  const _SectionHeader({required this.title, required this.count, this.color});
  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Row(children: [
          Container(width: 3, height: 16,
            decoration: BoxDecoration(
              color: color ?? Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('· $count', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ]),
      ),
    );
  }
}

class _TopicSliver extends ConsumerWidget {
  final List<Topic> topics;
  const _TopicSliver({required this.topics});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    return SliverList.separated(
      itemCount: topics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = topics[i];
        final s = subjects.where((s) => s.id == t.subjectId).firstOrNull;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SwipeToDelete(
            itemKey: ValueKey('topic-${t.id}'),
            title: 'Delete topic?',
            message:
                'This permanently removes “${t.title}” and its review history.',
            onDelete: () =>
                ref.read(topicCommandsProvider).deleteTopic(t.id),
            child: TopicCard(
              topic: t,
              subjectName: s?.name ?? '—',
              accent: s?.color ?? Theme.of(context).colorScheme.primary,
              relativeLabel: DateLabels.relative(t.nextDueAt),
              onTap: () => context.push('/topic/${t.id}'),
            ),
          ),
        ).animate(delay: (40 * i).ms).fadeIn(duration: 250.ms).slideY(begin: 0.05);
      },
    );
  }
}
