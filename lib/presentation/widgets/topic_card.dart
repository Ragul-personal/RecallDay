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

  const TopicCard({
    super.key,
    required this.topic,
    required this.subjectName,
    required this.accent,
    required this.relativeLabel,
    required this.onTap,
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

    final Color dueColor = overdue
        ? cs.error
        : due
            ? (brightness == Brightness.light
                ? StatusColors.warningLight
                : StatusColors.warningDark)
            : cs.onSurfaceVariant;

    return AppCard(
      onTap: onTap,
      accent: subjectColor,
      muted: paused,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md + 2,
        AppSpacing.md,
        AppSpacing.md + 2,
      ),
      child: Row(
        children: [
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
                      Icons.schedule_rounded,
                      size: 12.5,
                      color: dueColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      relativeLabel,
                      style: tt.labelSmall?.copyWith(
                        color: dueColor,
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
