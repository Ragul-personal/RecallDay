import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import 'app_card.dart';

/// Quick-look sheet for a topic.
///
/// Tapping a card opens this rather than pushing the full page: from a list
/// you usually want to check the details and either tick it off or move on,
/// and a sheet keeps you in place. "Open full topic" is right there for the
/// review ratings, notes and the stop-repetition control.
Future<void> showTopicSheet(
  BuildContext context,
  WidgetRef ref,
  String topicId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TopicSheet(topicId: topicId),
  );
}

class _TopicSheet extends ConsumerWidget {
  final String topicId;
  const _TopicSheet({required this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    // Watched, not read: ticking from inside the sheet updates it in place.
    final topics = ref.watch(topicsStreamProvider).valueOrNull ?? const [];
    final topic = topics.where((t) => t.id == topicId).firstOrNull;
    if (topic == null) return const SizedBox.shrink();

    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final subject = subjects.where((s) => s.id == topic.subjectId).firstOrNull;
    final accent = SubjectPalette.readable(
      subject?.color ?? cs.primary,
      theme.brightness,
    );

    final mastered = topic.status == TopicStatus.completed;
    final paused = topic.status == TopicStatus.paused;
    final success = theme.brightness == Brightness.light
        ? StatusColors.successLight
        : StatusColors.successDark;
    final notes = topic.notes?.trim() ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    subject?.name ?? 'No subject',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(topic.title, style: tt.headlineSmall),
            const SizedBox(height: AppSpacing.lg),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppPill(
                  mastered
                      ? 'Mastered'
                      : paused
                          ? 'Paused'
                          : '${DateLabels.relative(topic.nextDueAt)} · '
                              '${DateLabels.time(topic.nextDueAt)}',
                  icon: mastered
                      ? Icons.task_alt_rounded
                      : paused
                          ? Icons.pause_circle_outline_rounded
                          : Icons.event_rounded,
                  color: mastered
                      ? success
                      : topic.isOverdue
                          ? cs.error
                          : cs.primary,
                  tonal: true,
                ),
                AppPill(
                  '${topic.repetitions} review'
                  '${topic.repetitions == 1 ? '' : 's'}',
                  icon: Icons.check_circle_outline_rounded,
                ),
                if (topic.lastReviewedAt != null)
                  AppPill(
                    'Last ${DateLabels.relative(topic.lastReviewedAt!)}',
                    icon: Icons.history_rounded,
                  ),
              ],
            ),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  notes,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(height: 1.55),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            if (!mastered && topic.isDue)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('I revised this'),
                onPressed: () async {
                  final ok = await confirmCompletion(context, topic.title);
                  if (!ok || !context.mounted) return;
                  HapticFeedback.lightImpact();
                  final days = await ref
                      .read(topicCommandsProvider)
                      .markRevisedToday(topic.id);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          days <= 1
                              ? 'Done · back tomorrow'
                              : 'Done · next review in $days days',
                        ),
                      ),
                    );
                },
              ),
            if (!mastered && topic.isDue) const SizedBox(height: AppSpacing.sm),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              label: const Text('Open full topic'),
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/topic/${topic.id}');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The single confirmation shown before a topic is marked revised.
///
/// Shared so the tick on a card and the button inside the sheet ask the same
/// question in the same words.
Future<bool> confirmCompletion(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you sure you completed this topic?'),
      content: Text(
        '“$title” will be marked as revised and scheduled for its next '
        'review automatically.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes, completed'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
