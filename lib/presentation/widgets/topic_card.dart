import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/topic.dart';

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
    final cs = Theme.of(context).colorScheme;
    final overdue = topic.isOverdue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline, width: 0.6),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 4, height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topic.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(subjectName,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·', style: TextStyle(color: AppTheme.textMuted)),
                      ),
                      Text('${topic.estimatedMinutes} min',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                      if (topic.repetitions > 0) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('·', style: TextStyle(color: AppTheme.textMuted)),
                        ),
                        Text('${topic.repetitions}× reviewed',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                      ],
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: overdue ? cs.error.withValues(alpha: 0.16) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  relativeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: overdue ? cs.error : cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
