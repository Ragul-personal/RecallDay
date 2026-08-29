import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// A labelled block in a form.
///
/// The create screens previously alternated between `Text('Difficulty',
/// style: TextStyle(fontWeight: w600))` followed by an ad-hoc `SizedBox(height:
/// 6)`, and Material's own floating input labels — two labelling systems on one
/// screen, at two different sizes. This is the single pattern.
class FormSection extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;

  const FormSection({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: tt.labelSmall),
          ],
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
