import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';

class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final reviews = ref.watch(topicRepositoryProvider).allReviews();

    final completed = topics.where((t) => t.status == TopicStatus.completed).length;
    final overdue = topics.where((t) => t.isOverdue).length;
    final paused = topics.where((t) => t.status == TopicStatus.paused).length;

    // Reviews per day (last 30 days)
    final now = DateTime.now();
    final thirtyDays = List.generate(30, (i) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: 29 - i));
      final c = reviews.where((r) =>
          r.reviewedAt.year == day.year &&
          r.reviewedAt.month == day.month &&
          r.reviewedAt.day == day.day).length;
      return FlSpot(i.toDouble(), c.toDouble());
    });

    // Strongest / weakest by avg ease
    final easeBySubject = <String, List<double>>{};
    for (final t in topics) {
      easeBySubject.putIfAbsent(t.subjectId, () => []).add(t.ease);
    }
    final ranked = easeBySubject.entries
        .map((e) => MapEntry(e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Analytics'),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        sliver: SliverList.list(children: [
          Row(children: [
            _Tile(label: 'Total reviews', value: '${reviews.length}', accent: cs.primary),
            const SizedBox(width: 12),
            _Tile(label: 'Completed', value: '$completed', accent: const Color(0xFF8FD9C0)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _Tile(label: 'Overdue', value: '$overdue', accent: cs.error),
            const SizedBox(width: 12),
            _Tile(label: 'Paused', value: '$paused', accent: const Color(0xFFC586C0)),
          ]),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outline, width: 0.6),
            ),
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Reviews · last 30 days',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                height: 160,
                child: LineChart(LineChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: thirtyDays,
                      isCurved: true,
                      barWidth: 2.5,
                      color: cs.primary,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                )),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outline, width: 0.6),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Subjects · by retention', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (ranked.isEmpty)
                const Text('Not enough data yet.', style: TextStyle(color: AppTheme.textMuted))
              else
                for (final e in ranked) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Builder(builder: (_) {
                    final s = subjects.where((s) => s.id == e.key).firstOrNull;
                    return Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: s?.color ?? cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s?.name ?? '—')),
                      Text('ease ${e.value.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                    ]);
                  }),
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final String label, value;
  final Color accent;
  const _Tile({required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline, width: 0.6),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: accent)),
        ]),
      ),
    );
  }
}
