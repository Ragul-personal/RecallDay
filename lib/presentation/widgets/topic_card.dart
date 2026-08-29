import 'package:flutter/material.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/topic.dart';
import 'app_card.dart';

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
                  border: Border.all(
                    color: color.withValues(alpha: 0.55),
                    width: 2,
                  ),
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
