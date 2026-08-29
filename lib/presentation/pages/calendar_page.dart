import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/motion.dart';
import '../widgets/tab_app_bar.dart';

/// Calendar entry — one per (topic, projected due date). [isFirm] is true
/// only for the topic's currently scheduled `nextDueAt`; later entries on
/// the SR ladder are projections that will be recomputed after each review.
class _CalEntry {
  final Topic topic;
  final DateTime due;
  final bool isFirm;
  const _CalEntry(this.topic, this.due, this.isFirm);
}

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});
  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final engine = ref.watch(engineProvider);

    final entriesByDay = <DateTime, List<_CalEntry>>{};
    for (final t in topics) {
      if (t.status != TopicStatus.active) continue;
      final projected = engine.projectFutureDueDates(t);
      for (var i = 0; i < projected.length; i++) {
        final d = projected[i];
        final key = DateTime(d.year, d.month, d.day);
        entriesByDay
            .putIfAbsent(key, () => <_CalEntry>[])
            .add(_CalEntry(t, d, i == 0));
      }
    }

    final selectedKey =
        DateTime(_selected.year, _selected.month, _selected.day);
    final entries = (entriesByDay[selectedKey] ?? const <_CalEntry>[]).toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    return CustomScrollView(
      slivers: [
        const TabAppBar(title: 'Calendar'),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xs,
              AppSpacing.gutter,
              0,
            ),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: TableCalendar<_CalEntry>(
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365 * 2)),
                focusedDay: _focused,
                calendarFormat: _format,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableGestures: AvailableGestures.horizontalSwipe,
                selectedDayPredicate: (d) => _sameDay(d, _selected),
                onDaySelected: (sel, foc) => setState(() {
                  _selected = sel;
                  _focused = foc;
                }),
                onFormatChanged: (f) => setState(() => _format = f),
                onPageChanged: (f) => _focused = f,
                eventLoader: (day) =>
                    entriesByDay[DateTime(day.year, day.month, day.day)] ??
                    const [],
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: tt.labelSmall!,
                  weekendStyle: tt.labelSmall!,
                ),
                calendarBuilders: CalendarBuilders<_CalEntry>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    final firm = events.any((e) => e.isFirm);
                    return Positioned(
                      bottom: 5,
                      child: Container(
                        width: firm ? 5 : 4,
                        height: firm ? 5 : 4,
                        decoration: BoxDecoration(
                          color: firm
                              ? cs.primary
                              : cs.primary.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultTextStyle: tt.bodyMedium!,
                  weekendTextStyle: tt.bodyMedium!,
                  todayDecoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: tt.bodyMedium!.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: tt.bodyMedium!.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: tt.titleMedium!,
                  leftChevronIcon: Icon(
                    Icons.chevron_left_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  rightChevronIcon: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  headerPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: DateLabels.relative(_selected),
            count: entries.isEmpty ? null : entries.length,
            accent: cs.primary,
          ),
        ),
        if (entries.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.xl,
              ),
              child: Text('Nothing planned this day.', style: tt.bodySmall),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
            ),
            sliver: SliverList.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final e = entries[i];
                final s =
                    subjects.where((s) => s.id == e.topic.subjectId).firstOrNull;
                return FadeSlideIn(
                  index: i,
                  child: _PlannedRow(
                    entry: e,
                    subjectName: s?.name ?? 'No subject',
                    accent: s?.color ?? cs.primary,
                    onTap: () => context.push('/topic/${e.topic.id}'),
                  ),
                );
              },
            ),
          ),
        const SliverPadding(
          padding: EdgeInsets.only(bottom: AppSpacing.bottomInset),
        ),
      ],
    );
  }
}

class _PlannedRow extends StatelessWidget {
  final _CalEntry entry;
  final String subjectName;
  final Color accent;
  final VoidCallback onTap;

  const _PlannedRow({
    required this.entry,
    required this.subjectName,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final firm = entry.isFirm;
    final c = SubjectPalette.readable(accent, theme.brightness);

    return AppCard(
      onTap: onTap,
      accent: c,
      muted: !firm,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.md + 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(
                    color: firm ? null : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$subjectName · ${DateLabels.time(entry.due)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // "Projected" dates shift after every review, so they're marked
          // rather than presented as commitments.
          if (!firm)
            AppPill('Projected', color: cs.onSurfaceVariant)
          else
            AppPill('Scheduled', color: cs.primary, tonal: true),
        ],
      ),
    );
  }
}
