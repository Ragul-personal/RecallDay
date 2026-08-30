import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/motion.dart';
import '../widgets/revise_action.dart';
import '../widgets/tab_app_bar.dart';

/// What a calendar row represents.
enum _Kind {
  /// The topic's real `nextDueAt` — a commitment.
  scheduled,

  /// A later rung on the SR ladder. Recomputed after every review, so it's
  /// shown as a forecast rather than a promise.
  projected,

  /// A review that actually happened. This is what fills in the past — the
  /// calendar used to project forwards only, so every past date read
  /// "Nothing planned this day" even on days you'd studied.
  reviewed,
}

class _CalEntry {
  final Topic topic;
  final DateTime when;
  final _Kind kind;
  const _CalEntry(this.topic, this.when, this.kind);
}

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});
  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final success = StatusColors.success(context);

    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final engine = ref.watch(engineProvider);
    final reviews = ref.watch(topicRepositoryProvider).allReviews();

    final byDay = <DateTime, List<_CalEntry>>{};
    void add(_CalEntry e) =>
        byDay.putIfAbsent(_key(e.when), () => <_CalEntry>[]).add(e);

    // Forward: what's coming.
    for (final t in topics) {
      if (t.status != TopicStatus.active) continue;
      final projected = engine.projectFutureDueDates(t);
      for (var i = 0; i < projected.length; i++) {
        add(_CalEntry(
          t,
          projected[i],
          i == 0 ? _Kind.scheduled : _Kind.projected,
        ));
      }
    }

    // Backward: what actually happened. Reviews of deleted topics are skipped.
    final byId = {for (final t in topics) t.id: t};
    for (final r in reviews) {
      final t = byId[r.topicId];
      if (t == null) continue;
      add(_CalEntry(t, r.reviewedAt, _Kind.reviewed));
    }

    final entries = (byDay[_key(_selected)] ?? const <_CalEntry>[]).toList()
      ..sort((a, b) => a.when.compareTo(b.when));

    final doneCount = entries.where((e) => e.kind == _Kind.reviewed).length;
    final planCount = entries.length - doneCount;

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
                firstDay: DateTime.now().subtract(const Duration(days: 365 * 3)),
                lastDay: DateTime.now().add(const Duration(days: 365 * 2)),
                focusedDay: _focused,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableGestures: AvailableGestures.horizontalSwipe,
                selectedDayPredicate: (d) => _sameDay(d, _selected),
                onDaySelected: (sel, foc) => setState(() {
                  _selected = sel;
                  _focused = foc;
                }),
                onPageChanged: (f) => _focused = f,
                eventLoader: (day) => byDay[_key(day)] ?? const [],
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: tt.labelSmall!,
                  weekendStyle: tt.labelSmall!,
                ),
                calendarBuilders: CalendarBuilders<_CalEntry>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    // Green = you studied. Solid violet = firm commitment.
                    // Faded violet = forecast only.
                    final done = events.any((e) => e.kind == _Kind.reviewed);
                    final firm =
                        events.any((e) => e.kind == _Kind.scheduled);
                    final color = done
                        ? success
                        : firm
                            ? cs.primary
                            : cs.primary.withValues(alpha: 0.35);
                    return Positioned(
                      bottom: 5,
                      child: Container(
                        width: done || firm ? 5 : 4,
                        height: done || firm ? 5 : 4,
                        decoration: BoxDecoration(
                          color: color,
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
            trailing: entries.isEmpty
                ? null
                : Text(
                    [
                      if (doneCount > 0) '$doneCount done',
                      if (planCount > 0) '$planCount planned',
                    ].join(' · '),
                    style: tt.labelSmall,
                  ),
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
              child: Text(
                _key(_selected).isBefore(_key(DateTime.now()))
                    ? 'No reviews on this day.'
                    : 'Nothing planned this day.',
                style: tt.bodySmall,
              ),
            ),
          )
        else
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            sliver: SliverList.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final e = entries[i];
                final s = subjects
                    .where((s) => s.id == e.topic.subjectId)
                    .firstOrNull;
                return FadeSlideIn(
                  index: i,
                  child: _EntryRow(
                    entry: e,
                    subjectName: s?.name ?? 'No subject',
                    accent: s?.color ?? cs.primary,
                    onTap: () => context.push('/topic/${e.topic.id}'),
                    // Same pair of actions as Home, for anything due now.
                    actionable: e.kind == _Kind.scheduled && e.topic.isDue,
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

class _EntryRow extends ConsumerWidget {
  final _CalEntry entry;
  final String subjectName;
  final Color accent;
  final VoidCallback onTap;
  final bool actionable;

  const _EntryRow({
    required this.entry,
    required this.subjectName,
    required this.accent,
    required this.onTap,
    this.actionable = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final success = StatusColors.success(context);

    final done = entry.kind == _Kind.reviewed;
    final projected = entry.kind == _Kind.projected;
    final c = SubjectPalette.readable(accent, theme.brightness);

    return AppCard(
      onTap: onTap,
      accent: done ? success : c,
      muted: projected,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.md + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                        color: projected ? cs.onSurfaceVariant : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$subjectName · ${DateLabels.time(entry.when)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              switch (entry.kind) {
                _Kind.reviewed =>
                  AppPill('Reviewed', color: success, tonal: true),
                _Kind.scheduled =>
                  AppPill('Scheduled', color: cs.primary, tonal: true),
                _Kind.projected =>
                  AppPill('Forecast', color: cs.onSurfaceVariant),
              },
            ],
          ),
          if (actionable) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: ReviseActions(
                onDone: () => reviseTopic(
                  context,
                  ref,
                  entry.topic.id,
                  entry.topic.title,
                ),
                onMissed: () => markMissed(
                  context,
                  ref,
                  entry.topic.id,
                  entry.topic.title,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
