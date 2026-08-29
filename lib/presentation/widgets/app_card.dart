import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// The app's one card surface.
///
/// This exact `BoxDecoration` — container colour, 18px radius, hairline outline
/// — was copy-pasted into six screens, which is why the radii and paddings had
/// quietly drifted apart. Everything that needs a raised panel uses this.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Draws a 3px accent bar down the leading edge — used to carry a subject's
  /// colour without adding another element to the row.
  final Color? accent;

  /// Slightly recedes the card (used for "projected", not-yet-firm entries).
  final bool muted;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.onLongPress,
    this.accent,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.lg);

    Widget content = Padding(padding: padding, child: child);

    if (accent != null) {
      // The accent bar is drawn as a Positioned overlay, NOT as a stretched
      // Row child.
      //
      // `Row(crossAxisAlignment: stretch)` makes RenderFlex pass
      // `BoxConstraints.tightFor(height: constraints.maxHeight)` to its
      // children. List items are laid out with maxHeight: infinity, so that's
      // an infinite tight height — a layout exception, and in a release build
      // a failed render paints nothing at all. Every card with an accent (i.e.
      // every topic row on Home, in a subject, and in the calendar) silently
      // disappeared; cards without one still rendered, which is why subjects
      // stayed visible.
      //
      // In a Stack the non-positioned child establishes the height, and the
      // bar then stretches to it via top/bottom — no unbounded constraint.
      content = Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: content,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(
              color: muted ? accent!.withValues(alpha: 0.4) : accent!,
            ),
          ),
        ],
      );
    }

    return Material(
      color: cs.surfaceContainer,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        // Let the tap ripple read as violet rather than default grey.
        splashColor: cs.primary.withValues(alpha: 0.06),
        highlightColor: cs.primary.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: muted ? cs.outlineVariant : cs.outline,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Small rounded label. Replaces four near-identical inline pill containers.
class AppPill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  /// Filled tint vs. plain neutral background.
  final bool tonal;

  const AppPill(
    this.text, {
    super.key,
    this.color,
    this.icon,
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = color ?? cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: tonal
            ? c.withValues(alpha: 0.12)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tonal ? c : cs.onSurfaceVariant),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: tonal ? c : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Consistent section heading for the scrollable screens.
class SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final Color? accent;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xxl,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(title, style: tt.titleMedium),
          if (count != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: (accent ?? cs.onSurfaceVariant).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent ?? cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
