import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';

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
    final cs = Theme.of(context).colorScheme;
    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final engine = ref.watch(engineProvider);

    // Build the (topic × projected-due-date) flat list and bucket by day.
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
    final entriesOnSelected = (entriesByDay[selectedKey] ?? const <_CalEntry>[])
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Calendar'),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outline, width: 0.6),
            ),
            padding: const EdgeInsets.all(8),
            child: TableCalendar<_CalEntry>(
              firstDay: DateTime.now().subtract(const Duration(days: 365)),
              lastDay: DateTime.now().add(const Duration(days: 365 * 2)),
              focusedDay: _focused,
              calendarFormat: _format,
              startingDayOfWeek: StartingDayOfWeek.monday,
              selectedDayPredicate: (d) => _sameDay(d, _selected),
              onDaySelected: (sel, foc) =>
                  setState(() { _selected = sel; _focused = foc; }),
              onFormatChanged: (f) => setState(() => _format = f),
              eventLoader: (day) =>
                  entriesByDay[DateTime(day.year, day.month, day.day)] ??
                  const [],
              calendarBuilders: CalendarBuilders<_CalEntry>(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  final hasFirm = events.any((e) => e.isFirm);
                  return Positioned(
                    bottom: 4,
                    child: Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: hasFirm
                            ? cs.primary
                            : cs.primary.withValues(alpha: 0.40),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.18),
                    shape: BoxShape.circle),
                todayTextStyle: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.w600),
                selectedDecoration: BoxDecoration(
                    color: cs.primary, shape: BoxShape.circle),
                outsideDaysVisible: false,
              ),
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonShowsNext: false,
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Row(children: [
            Text(DateLabels.relative(_selected),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(width: 8),
            Text('· ${entriesOnSelected.length} planned',
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 13)),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            _LegendDot(color: cs.primary, label: 'Scheduled'),
            const SizedBox(width: 12),
            _LegendDot(
                color: cs.primary.withValues(alpha: 0.40),
                label: 'Projected'),
          ]),
        ),
      ),
      if (entriesOnSelected.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text('Nothing planned this day.',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
        )
      else
        SliverList.separated(
          itemCount: entriesOnSelected.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = entriesOnSelected[i];
            final s =
                subjects.where((s) => s.id == e.topic.subjectId).firstOrNull;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _PlannedEntryCard(
                entry: e,
                subjectName: s?.name ?? '—',
                accent: s?.color ?? cs.primary,
                onTap: () => context.push('/topic/${e.topic.id}'),
              ),
            );
          },
        ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
    ]);
  }
}

class _PlannedEntryCard extends StatelessWidget {
  final _CalEntry entry;
  final String subjectName;
  final Color accent;
  final VoidCallback onTap;
  const _PlannedEntryCard({
    required this.entry,
    required this.subjectName,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = entry.topic;
    final firm = entry.isFirm;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: firm
                    ? cs.outline
                    : cs.outline.withValues(alpha: 0.5),
                width: 0.6),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(children: [
            Container(
              width: 4, height: 36,
              decoration: BoxDecoration(
                color: firm ? accent : accent.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('$subjectName · ${DateLabels.time(entry.due)}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12.5)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: firm
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                firm ? 'Scheduled' : 'Projected',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: firm ? cs.primary : AppTheme.textMuted,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
