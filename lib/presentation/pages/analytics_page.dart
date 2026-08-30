import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/motion.dart';
import '../widgets/tab_app_bar.dart';

/// Progress.
///
/// Rebuilt around what the app actually records now. Two things were dropped:
///
///   • **Retention by subject.** It ranked subjects by SM-2 ease, but ease only
///     moves when the user grades a recall, and grading was replaced by a
///     single Done action that always records the neutral rating. Every subject
///     therefore sat at exactly 2.5 forever — an identical bar on every row,
///     dressed up as insight.
///   • **Paused / active tile counts.** Pausing is rare and the number told the
///     user nothing they could act on.
///
/// What replaces them is drawn only from things the user actually did: days
/// they revised, revisions completed, topics they chose to master, and what is
/// due next.
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final light = theme.brightness == Brightness.light;

    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final reviews = ref.watch(topicRepositoryProvider).allReviews();
    final streak = ref.watch(streakDaysProvider);
    final best = ref.watch(bestStreakProvider);
    final activity = ref.watch(recentActivityProvider);

    final success = light ? StatusColors.successLight : StatusColors.successDark;
    final warning = light ? StatusColors.warningLight : StatusColors.warningDark;

    if (topics.isEmpty && reviews.isEmpty) {
      return const CustomScrollView(
        slivers: [
          TabAppBar(title: 'Progress'),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.insights_rounded,
              title: 'Nothing to show yet',
              subtitle:
                  'Once you start revising, your streak and history will '
                  'build up here.',
            ),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final thisWeek = reviews.where((r) => r.reviewedAt.isAfter(weekAgo)).length;

    final mastered =
        topics.where((t) => t.status == TopicStatus.completed).length;
    final dueToday = ref.watch(dueTodayProvider).length +
        ref.watch(overdueProvider).length;

    return CustomScrollView(
      slivers: [
        const TabAppBar(title: 'Progress'),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xs,
            AppSpacing.gutter,
            AppSpacing.bottomInset,
          ),
          sliver: SliverList.list(
            children: [
              FadeSlideIn(
                child: _StreakCard(
                  streak: streak,
                  best: best,
                  activity: activity,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                index: 1,
                child: Row(
                  children: [
                    _Stat(
                      label: 'Revisions',
                      value: reviews.length,
                      caption: 'all time',
                      accent: cs.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Stat(
                      label: 'This week',
                      value: thisWeek,
                      caption: 'last 7 days',
                      accent: success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                index: 2,
                child: Row(
                  children: [
                    _Stat(
                      label: 'Due now',
                      value: dueToday,
                      caption: dueToday == 0 ? 'all clear' : 'to revise',
                      accent: dueToday > 0 ? warning : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Stat(
                      label: 'Mastered',
                      value: mastered,
                      caption: 'stopped',
                      accent: mastered > 0 ? success : cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (subjects.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxl),
                Text('By subject', style: tt.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'How far through each subject you are.',
                  style: tt.labelSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < subjects.length; i++)
                  Builder(
                    builder: (_) {
                      final s = subjects[i];
                      final mine =
                          topics.where((t) => t.subjectId == s.id).toList();
                      return FadeSlideIn(
                        index: i,
                        child: Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _SubjectProgress(
                            name: s.name,
                            color: SubjectPalette.readable(
                              s.color,
                              theme.brightness,
                            ),
                            total: mine.length,
                            mastered: mine
                                .where((t) =>
                                    t.status == TopicStatus.completed)
                                .length,
                            due: mine.where((t) => t.isDue).length,
                            onTap: () => context.push('/subject/${s.id}'),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Streak, best streak, and a 30-day activity strip.
///
/// The strip replaces a smoothed line chart. With one or two revisions on a
/// typical day the line was mostly a jagged path between 0 and 1, which read
/// as noise; a per-day cell answers "did I study that day?" at a glance, which
/// is the actual question.
class _StreakCard extends StatelessWidget {
  final int streak;
  final int best;
  final List<int> activity;

  const _StreakCard({
    required this.streak,
    required this.best,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final active = streak > 0;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: active ? cs.primary : cs.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AnimatedCount(
                          streak,
                          style: tt.displaySmall?.copyWith(
                            color: active ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          streak == 1 ? 'day streak' : 'days in a row',
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                    Text(
                      best > 0 ? 'Best so far: $best days' : 'Revise to start one',
                      style: tt.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _ActivityStrip(activity: activity),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('30 days ago', style: tt.labelSmall),
              Text('Today', style: tt.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityStrip extends StatelessWidget {
  final List<int> activity;
  const _ActivityStrip({required this.activity});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = activity.length;

    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                // Four steps rather than a continuous scale: at a handful of
                // revisions a day, a gradient would be indistinguishable.
                color: switch (activity[i]) {
                  0 => cs.surfaceContainerHighest,
                  1 => cs.primary.withValues(alpha: 0.35),
                  2 => cs.primary.withValues(alpha: 0.65),
                  _ => cs.primary,
                },
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final String caption;
  final Color accent;

  const _Stat({
    required this.label,
    required this.value,
    required this.caption,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: tt.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            AnimatedCount(
              value,
              style: tt.displaySmall?.copyWith(color: accent),
            ),
            const SizedBox(height: 2),
            Text(caption, style: tt.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// One subject's mastery progress.
///
/// Mastered-out-of-total is something the user directly controls, unlike the
/// ease figure this replaced.
class _SubjectProgress extends StatelessWidget {
  final String name;
  final Color color;
  final int total;
  final int mastered;
  final int due;
  final VoidCallback onTap;

  const _SubjectProgress({
    required this.name,
    required this.color,
    required this.total,
    required this.mastered,
    required this.due,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pct = total == 0 ? 0.0 : mastered / total;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
              ),
              if (due > 0)
                AppPill('$due due', color: color, tonal: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct),
              duration: AppMotion.slow,
              curve: AppMotion.curve,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            total == 0
                ? 'No topics yet'
                : '$mastered of $total mastered',
            style: tt.labelSmall,
          ),
        ],
      ),
    );
  }
}
