import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Shared top bar for the four tab screens, so titles, actions and
/// scroll-under behaviour are identical across them.
///
/// Each tab previously declared its own `SliverAppBar` with slightly different
/// settings, which is why titles sat at different sizes and offsets as you
/// moved between tabs.
class TabAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const TabAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SliverAppBar(
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: AppSpacing.gutter,
      toolbarHeight: subtitle == null ? 58 : 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: tt.headlineSmall),
          if (subtitle != null) Text(subtitle!, style: tt.labelSmall),
        ],
      ),
      actions: [...actions, const SizedBox(width: AppSpacing.sm)],
    );
  }
}
