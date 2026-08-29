import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../providers/providers.dart';

/// The one revision flow, shared by Home, Calendar and the topic page.
///
/// There is a single question and a single outcome, so the three entry points
/// can't drift apart in wording or behaviour:
///
///   "Did you complete your revision in this topic?"
///     Yes -> the review is recorded and the next one scheduled
///     No  -> nothing changes; the topic stays due
///
/// Answering yes moves the topic's next due date at least a day forward, so it
/// drops off today's list — a topic is only ever revised once per due date.
Future<bool> confirmRevision(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Did you complete your revision in this topic?'),
      content: Text(
        '“$title” will be marked as revised and its next review scheduled '
        'automatically.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No, not yet'),
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

/// The compact "Revise" affordance shown on a due topic's card.
class ReviseButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool compact;

  const ReviseButton({
    super.key,
    required this.onPressed,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.md : AppSpacing.lg,
            vertical: compact ? AppSpacing.sm + 1 : AppSpacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 15, color: cs.primary),
              const SizedBox(width: 5),
              Text(
                'Revise',
                style: tt.labelSmall?.copyWith(
                  color: cs.primary,
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
