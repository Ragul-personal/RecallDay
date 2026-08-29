import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// Retention was previously reported as a raw "ease 2.35" number, which is an
/// internal SM-2 parameter and means nothing to a user. It's now shown as a
/// proportional bar with a plain-language label; the number is still there for
/// anyone who wants it, just no longer the headline.
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

    final completed =
        topics.where((t) => t.status == TopicStatus.completed).length;
    final overdue = topics.where((t) => t.isOverdue).length;
    final active = topics.where((t) => t.status == TopicStatus.active).length;

    final success = light ? StatusColors.successLight : StatusColors.successDark;
    final warning = light ? StatusColors.warningLight : StatusColors.warningDark;

    if (reviews.isEmpty && topics.isEmpty) {
      return const CustomScrollView(
        slivers: [
          TabAppBar(title: 'Progress'),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.insights_rounded,
              title: 'No progress yet',
              subtitle:
                  'Once you start reviewing topics, your streaks and retention '
                  'will show up here.',
            ),
          ),
        ],
      );
    }

    // Reviews per day, last 30 days.
    final now = DateTime.now();
    final spots = List.generate(30, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 29 - i));
      final c = reviews
          .where((r) =>
              r.reviewedAt.year == day.year &&
              r.reviewedAt.month == day.month &&
              r.reviewedAt.day == day.day)
          .length;
      return FlSpot(i.toDouble(), c.toDouble());
    });
    final peak = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    final last30 = spots.fold<double>(0, (a, s) => a + s.y).round();

    // Average ease per subject, ranked.
    final easeBySubject = <String, List<double>>{};
    for (final t in topics) {
      easeBySubject.putIfAbsent(t.subjectId, () => []).add(t.ease);
    }
    final ranked = easeBySubject.entries
        .map((e) =>
            MapEntry(e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
                child: Row(
                  children: [
                    _Stat(
                      label: 'Reviews',
                      value: reviews.length,
                      accent: cs.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Stat(
                      label: 'Active',
                      value: active,
                      accent: success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FadeSlideIn(
                index: 1,
                child: Row(
                  children: [
                    _Stat(
                      label: 'Overdue',
                      value: overdue,
                      accent: overdue > 0 ? cs.error : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Stat(
                      label: 'Completed',
                      value: completed,
                      accent: warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                index: 2,
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Last 30 days', style: tt.titleMedium),
                          ),
                          Text('$last30 reviews', style: tt.labelSmall),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 140,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: peak < 3 ? 3 : peak * 1.25,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: const FlTitlesData(show: false),
                            lineTouchData: const LineTouchData(enabled: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                curveSmoothness: 0.28,
                                barWidth: 2.5,
                                color: cs.primary,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      cs.primary.withValues(alpha: 0.22),
                                      cs.primary.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                index: 3,
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Retention by subject', style: tt.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'How well material is sticking, based on your ratings.',
                        style: tt.labelSmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (ranked.isEmpty)
                        Text('Not enough data yet.', style: tt.bodySmall)
                      else
                        for (final e in ranked)
                          Builder(
                            builder: (_) {
                              final s = subjects
                                  .where((s) => s.id == e.key)
                                  .firstOrNull;
                              return _RetentionBar(
                                name: s?.name ?? 'No subject',
                                color: SubjectPalette.readable(
                                  s?.color ?? cs.primary,
                                  theme.brightness,
                                ),
                                ease: e.value,
                              );
                            },
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;

  const _Stat({
    required this.label,
    required this.value,
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
          ],
        ),
      ),
    );
  }
}

/// One subject's retention, as a proportional bar.
///
/// Ease is clamped to [1.3, 3.0] by the engine, so that range maps to 0–100%.
class _RetentionBar extends StatelessWidget {
  final String name;
  final Color color;
  final double ease;

  const _RetentionBar({
    required this.name,
    required this.color,
    required this.ease,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pct = ((ease - 1.3) / (3.0 - 1.3)).clamp(0.0, 1.0);

    final label = switch (pct) {
      > 0.75 => 'Strong',
      > 0.45 => 'Steady',
      > 0.2 => 'Shaky',
      _ => 'Needs work',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium,
                ),
              ),
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
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
        ],
      ),
    );
  }
}
