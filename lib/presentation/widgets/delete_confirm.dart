import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_tokens.dart';

/// Shared confirmation dialog.
///
/// Always pops with the DIALOG's context, not the caller's — popping the
/// caller's context targets the nearest navigator above that widget, which is
/// only the dialog's route by coincidence.
///
/// [destructive] tints the confirm button with the error colour. Restore flows
/// reuse this dialog but aren't destructive, so they turn it off.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// Swipe-left-to-delete wrapper for list rows.
///
/// Deleting used to be reachable only by drilling into a detail page, which is
/// why "I can't delete it" was a fair complaint even though the delete code
/// existed. This puts it on the rows themselves.
class SwipeToDelete extends StatelessWidget {
  final Key itemKey;
  final Widget child;
  final String title;
  final String message;

  /// Performs the delete. Called only after the user confirms.
  final Future<void> Function() onDelete;

  const SwipeToDelete({
    super.key,
    required this.itemKey,
    required this.child,
    required this.title,
    required this.message,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: itemKey,
      direction: DismissDirection.endToStart,
      // A little further than the default 40%, so a casual sideways scroll
      // doesn't feel like it's about to delete something.
      dismissThresholds: const {DismissDirection.endToStart: 0.45},
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Icon(Icons.delete_outline_rounded, color: cs.error, size: 22),
      ),
      // The delete happens here rather than in onDismissed so the row is only
      // removed from the tree once the data is actually gone.
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        final ok = await confirmDelete(
          context,
          title: title,
          message: message,
        );
        if (!ok) return false;
        await onDelete();
        return true;
      },
      child: child,
    );
  }
}
