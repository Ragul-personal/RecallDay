import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../providers/providers.dart';

/// The revision actions shared by Home, Calendar and the topic page.
///
/// Two outcomes, each with its own button on the card so neither is hidden
/// behind a dialog:
///
///   Done     -> the revision is recorded and the next one scheduled
///   Not done -> the revision is rolled to tomorrow, progress untouched
///
/// Either way the topic leaves today's list, so it can't be actioned twice for
/// the same date.
Future<bool> confirmRevision(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Completed this revision?'),
      content: Text(
        '“$title” will be marked as revised and its next review scheduled '
        'automatically.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
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

/// Confirmation for the negative action.
Future<bool> confirmMissed(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Didn’t complete this revision?'),
      content: Text(
        '“$title” will move to tomorrow. Nothing is recorded and your progress '
        'on this topic stays exactly where it is.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Move to tomorrow'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Ask, then roll the topic to tomorrow without recording a review.
Future<void> markMissed(
  BuildContext context,
  WidgetRef ref,
  String topicId,
  String title,
) async {
  HapticFeedback.selectionClick();
  final ok = await confirmMissed(context, title);
  if (!ok || !context.mounted) return;

  await ref.read(topicCommandsProvider).markNotRevised(topicId);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Moved to tomorrow · progress kept')),
    );
}

/// Ask, then record. Reports back when the topic returns.
Future<void> reviseTopic(
  BuildContext context,
  WidgetRef ref,
  String topicId,
  String title,
) async {
  HapticFeedback.selectionClick();
  final ok = await confirmRevision(context, title);
  // "No" leaves the topic untouched and still due, exactly as it was.
  if (!ok || !context.mounted) return;

  HapticFeedback.lightImpact();
  final days = await ref.read(topicCommandsProvider).markRevisedToday(topicId);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          days <= 1 ? 'Revised · back tomorrow' : 'Revised · next in $days days',
        ),
      ),
    );
}

/// The pair of actions on a due topic's card.
///
/// Both outcomes are visible and distinct: a green tick for done, a muted
/// amber cross for not done. A single button couldn't say which of the two it
/// meant without the user opening a dialog to find out.
class ReviseActions extends StatelessWidget {
  final VoidCallback onDone;
  final VoidCallback onMissed;

  const ReviseActions({
    super.key,
    required this.onDone,
    required this.onMissed,
  });

  @override
  Widget build(BuildContext context) {
    final success = StatusColors.success(context);
    final warning = StatusColors.warning(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Action(
          icon: Icons.close_rounded,
          label: 'Not done',
          color: warning,
          onTap: onMissed,
        ),
        const SizedBox(width: AppSpacing.sm),
        _Action(
          icon: Icons.check_rounded,
          label: 'Done',
          color: success,
          onTap: onDone,
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
