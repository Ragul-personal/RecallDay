import 'package:flutter/material.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/topic.dart';
import 'app_card.dart';
import 'revise_action.dart';

/// A topic row.
///
/// The topic title is the primary line and the subject sits beneath it as
/// context. (It was the other way round — subject first, title second — which
/// buried the thing you're actually scanning for behind a label repeated on
/// every row of a subject.)
///
/// Only the essentials are on the card; everything else lives in the detail
/// sheet that opens on tap.
class TopicCard extends StatelessWidget {
  final Topic topic;
  final String subjectName;
  final Color accent;
  final String relativeLabel;
  final VoidCallback onTap;

  /// Shown only for topics that are actually due. Both must be supplied
  /// together — offering one without the other is what made the old single
  /// button ambiguous.
  final VoidCallback? onDone;
  final VoidCallback? onMissed;

  const TopicCard({
    super.key,
    required this.topic,
    required this.subjectName,
    required this.accent,
    required this.relativeLabel,
    required this.onTap,
    this.onDone,
    this.onMissed,
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

    final statusLabel = mastered
        ? 'Mastered'
        : paused
            ? 'Paused'
            : relativeLabel;
    final statusColor = mastered
        ? success
        : paused
            ? cs.onSurfaceVariant
            : dueColor;

    final actionable = onDone != null && onMissed != null;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Primary: the topic itself.
                Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
                const SizedBox(height: 4),
                // Secondary: which subject it belongs to.
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: subjectColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(color: subjectColor),
                      ),
                    ),
                    Text('  ·  ', style: tt.labelSmall),
                    Icon(
                      mastered
                          ? Icons.check_circle_outline_rounded
                          : paused
                              ? Icons.pause_circle_outline_rounded
                              : Icons.schedule_rounded,
                      size: 12.5,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: tt.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
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
          // Full-width row beneath the title rather than squeezed alongside
          // it: two labelled buttons need room to stay legible on a narrow
          // phone, and a cramped pair invites the wrong tap.
          if (actionable) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: ReviseActions(onDone: onDone!, onMissed: onMissed!),
            ),
          ],
        ],
      ),
    );
  }
}
