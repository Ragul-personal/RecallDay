import 'package:flutter/material.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import 'app_card.dart';

/// A topic row — what a subject's page is a list of.
///
/// A topic has no schedule of its own, so this row answers a different
/// question from [SubtopicCard]: not "when do I revise this?" but "how much is
/// in here, and is any of it waiting?". The counts are the whole content, and
/// a topic with nothing due says so rather than showing an empty pill.
class TopicCard extends StatelessWidget {
  final String title;
  final Color accent;
  final int subtopicCount;
  final int dueCount;
  final int masteredCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const TopicCard({
    super.key,
    required this.title,
    required this.accent,
    required this.subtopicCount,
    required this.dueCount,
    required this.masteredCount,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final c = SubjectPalette.readable(accent, theme.brightness);
    final success = StatusColors.success(context);

    final allMastered = subtopicCount > 0 && masteredCount == subtopicCount;

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      accent: allMastered ? success : c,
      muted: allMastered,
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
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  subtopicCount == 0
                      ? 'No subtopics yet'
                      : '$subtopicCount subtopic'
                          '${subtopicCount == 1 ? '' : 's'}'
                          '${masteredCount > 0 ? ' · $masteredCount mastered' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall,
                ),
              ],
            ),
          ),
          if (dueCount > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            AppPill(
              '$dueCount due',
              color: StatusColors.warning(context),
              tonal: true,
            ),
          ],
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
