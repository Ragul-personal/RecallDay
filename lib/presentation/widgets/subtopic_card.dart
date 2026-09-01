import 'package:flutter/material.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/subtopic.dart';
import 'app_card.dart';
import 'revise_action.dart';

/// A subtopic row — the card the Today screen is made of.
///
/// Three lines, in the order you'd say them out loud when deciding whether to
/// start: **what** to revise, **which topic** it belongs to, and **which
/// subject** that topic is in. The leaf title is the thing being scanned for,
/// so it leads; the two ancestors follow at decreasing weight rather than
/// being crammed into one breadcrumb, which at label size turns into a strip
/// of grey text with no obvious reading order.
///
/// Only the essentials are on the card; everything else lives on the detail
/// page that opens on tap.
class SubtopicCard extends StatelessWidget {
  final Subtopic subtopic;

  /// Parent topic. Null only if the topic went missing — the row still has to
  /// draw rather than disappear, which is how an orphan gets noticed.
  final String? topicName;
  final String subjectName;
  final Color accent;
  final String relativeLabel;
  final VoidCallback onTap;

  /// Shown only for subtopics that are actually due. Both must be supplied
  /// together — offering one without the other is what made the old single
  /// button ambiguous.
  final VoidCallback? onDone;
  final VoidCallback? onMissed;

  const SubtopicCard({
    super.key,
    required this.subtopic,
    required this.topicName,
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

    final overdue = subtopic.isOverdue;
    final due = subtopic.isDue;
    final subjectColor = SubjectPalette.readable(accent, theme.brightness);
    final paused = subtopic.status == SubtopicStatus.paused;
    final mastered = subtopic.status == SubtopicStatus.completed;
    final success = StatusColors.success(context);

    final Color dueColor = overdue
        ? cs.error
        : due
            ? StatusColors.warning(context)
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
                    // 1 — the subtopic: what you are actually revising.
                    Text(
                      subtopic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    // 2 — the topic it sits under.
                    Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            topicName ?? 'No topic',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 3 — the subject, carrying its colour, plus when it's due.
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
                            style:
                                tt.labelSmall?.copyWith(color: subjectColor),
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
          // Full-width row beneath the titles rather than squeezed alongside
          // them: two labelled buttons need room to stay legible on a narrow
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
