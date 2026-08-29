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
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            color: muted ? accent!.withValues(alpha: 0.4) : accent,
          ),
          Expanded(child: content),
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
