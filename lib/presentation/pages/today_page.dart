import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_card.dart';
import '../widgets/delete_confirm.dart';
import '../widgets/empty_state.dart';
import '../widgets/motion.dart';
import '../widgets/revise_action.dart';
import '../widgets/tab_app_bar.dart';
import '../widgets/topic_card.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final due = ref.watch(dueTodayProvider);
    final overdue = ref.watch(overdueProvider);
    final streak = ref.watch(streakDaysProvider);
    final doneToday = ref.watch(reviewedTodayCountProvider);

    final pending = overdue.length + due.length;
    final isDark = theme.brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
            TabAppBar(
              title: _greeting(),
              subtitle: DateLabels.fullDate(DateTime.now()),
              actions: [
                IconButton(
                  tooltip: isDark ? 'Light theme' : 'Dark theme',
                  icon: Icon(
                    isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                  onPressed: () => ref
                      .read(themeModeProvider.notifier)
                      .toggle(theme.brightness),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),

            // One combined progress card rather than three competing stat
            // tiles — the day's completion is the thing you actually want.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.xs,
                  AppSpacing.gutter,
                  0,
                ),
                child: FadeSlideIn(
                  child: _DayProgressCard(
                    pending: pending,
                    doneToday: doneToday,
                    streak: streak,
                  ),
                ),
              ),
            ),

            if (overdue.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Overdue',
                  count: overdue.length,
                  accent: cs.error,
                ),
              ),
              _TopicSliver(topics: overdue, completable: true),
            ],

            if (due.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Due today',
                  count: due.length,
                  accent: cs.primary,
                ),
              ),
              _TopicSliver(topics: due, completable: true),
            ],

            if (overdue.isEmpty && due.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Nothing to revise yet',
                  subtitle:
                      'Add your first topic and RecallDay will remind you to '
                      'review it at the right moments.',
                  action: FilledButton.icon(
                    onPressed: () => context.push('/create/topic'),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add a topic'),
                  ),
                ),
              ),

        const SliverPadding(
          padding: EdgeInsets.only(bottom: AppSpacing.bottomInset),
        ),
      ],
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// Header card: how much of today is left, plus streak.
class _DayProgressCard extends StatelessWidget {
  final int pending;
  final int doneToday;
  final int streak;

  const _DayProgressCard({
    required this.pending,
    required this.doneToday,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final total = pending + doneToday;
    final progress = total == 0 ? 1.0 : doneToday / total;
    // Three distinct states, not two. "All caught up" is a reward for having
    // cleared something; saying it on a day with nothing scheduled claims
    // credit the user didn't earn.
    final nothingDue = pending == 0 && doneToday == 0;
    final allDone = pending == 0 && doneToday > 0;

    final success = theme.brightness == Brightness.light
        ? StatusColors.successLight
        : StatusColors.successDark;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nothingDue
                          ? 'No revisions today'
                          : allDone
                              ? 'All caught up'
                              : '$pending to revise',
                      style: tt.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nothingDue
                          ? 'Nothing is scheduled for today'
                          : allDone
                              ? '$doneToday reviewed today'
                              : '$doneToday of $total done today',
                      style: tt.bodySmall,
                    ),
                  ],
                ),
              ),
              if (streak > 0)
                AppPill(
                  '$streak day${streak == 1 ? '' : 's'}',
                  icon: Icons.local_fire_department_rounded,
                  color: allDone ? success : cs.primary,
                  tonal: true,
                ),
            ],
          ),
          // No bar on a day with nothing scheduled: a full progress bar there
          // would read as an achievement the user didn't earn.
          if (!nothingDue) ...[
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: AppMotion.slow,
                curve: AppMotion.curve,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(
                    allDone ? success : cs.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopicSliver extends ConsumerWidget {
  final List<Topic> topics;

  /// Rows in this list are due, so they carry a Revise button.
  final bool completable;

  const _TopicSliver({required this.topics, this.completable = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final cs = Theme.of(context).colorScheme;

    return SliverList.separated(
      itemCount: topics.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) {
        final t = topics[i];
        final s = subjects.where((s) => s.id == t.subjectId).firstOrNull;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: FadeSlideIn(
            index: i,
            child: SwipeToDelete(
              itemKey: ValueKey('topic-${t.id}'),
              title: 'Delete topic?',
              message:
                  'This permanently removes “${t.title}” and its review history.',
              onDelete: () => ref.read(topicCommandsProvider).deleteTopic(t.id),
              child: TopicCard(
                topic: t,
                subjectName: s?.name ?? 'No subject',
                accent: s?.color ?? cs.primary,
                relativeLabel: DateLabels.relative(t.nextDueAt),
                onTap: () => context.push('/topic/${t.id}'),
                onDone: completable
                    ? () => reviseTopic(context, ref, t.id, t.title)
                    : null,
                onMissed: completable
                    ? () => markMissed(context, ref, t.id, t.title)
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

}
