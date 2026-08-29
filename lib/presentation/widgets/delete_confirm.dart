import 'package:flutter/material.dart';

/// Shared destructive-action confirmation.
///
/// Always pops with the DIALOG's context, not the caller's — popping the
/// caller's context targets the nearest navigator above that widget, which is
/// only the dialog's route by coincidence.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
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
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline, color: cs.error),
      ),
      // The delete happens here rather than in onDismissed so the row is only
      // removed from the tree once the data is actually gone.
      confirmDismiss: (_) async {
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
