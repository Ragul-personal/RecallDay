import 'package:flutter/material.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/topic.dart';
import 'app_card.dart';

/// A topic row.
///
/// The old version packed subject · minutes · "N× reviewed" onto one metadata
/// line separated by middots, which wrapped and truncated on narrow phones.
/// The row now leads with the subject (the thing you scan for), and the due
/// label carries the urgency colour rather than a separate badge.
class TopicCard extends StatelessWidget {
  final Topic topic;
  final String subjectName;
  final Color accent;
  final String relativeLabel;
  final VoidCallback onTap;

  /// Shows a tick control on the leading edge for marking today's revision
  /// done. Only passed for topics that are actually due — a card for something
  /// due next week has nothing to tick off yet.
  final VoidCallback? onComplete;

  const TopicCard({
    super.key,
    required this.topic,
    required this.subjectName,
    required this.accent,
    required this.relativeLabel,
    required this.onTap,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final brightness = theme.brightness;

    final overdue = topic.isOverdue;
    final due = topic.isDue;
    final subjectColor = SubjectPalette.readable(accent, brightness);
    final paused = topic.status == TopicStatus.paused;
    final mastered = topic.status == TopicStatus.completed;
    final success = brightness == Brightness.light
        ? StatusColors.successLight
        : StatusColors.successDark;

    final Color dueColor = overdue
        ? cs.error
        : due
            ? (brightness == Brightness.light
                ? StatusColors.warningLight
                : StatusColors.warningDark)
            : cs.onSurfaceVariant;

    return AppCard(
      onTap: onTap,
      accent: mastered ? success : subjectColor,
      muted: paused || mastered,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.md + 2,
      ),
      child: Row(
        children: [
          if (onComplete != null) ...[
            _CompleteTick(color: subjectColor, onTap: onComplete!),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(
                          color: subjectColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (paused) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.pause_circle_outline_rounded,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                    if (mastered) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.task_alt_rounded, size: 13, color: success),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      mastered
                          ? Icons.check_circle_outline_rounded
                          : Icons.schedule_rounded,
                      size: 12.5,
                      color: mastered ? success : dueColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      // A mastered topic has no next due date to report, so
                      // showing its stale one would be misleading.
                      mastered
                          ? 'Mastered'
                          : paused
                              ? 'Paused'
                              : relativeLabel,
                      style: tt.labelSmall?.copyWith(
                        color: mastered ? success : dueColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '  ·  ${topic.estimatedMinutes} min',
                      style: tt.labelSmall,
                    ),
                    if (topic.repetitions > 0)
                      Flexible(
                        child: Text(
                          '  ·  ${topic.repetitions}× done',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

/// The "revised it" tick.
///
/// Deliberately a large circular target (44px, the platform minimum) with its
/// own ink response, so tapping it never opens the topic by accident.
class _CompleteTick extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _CompleteTick({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Mark as revised',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
