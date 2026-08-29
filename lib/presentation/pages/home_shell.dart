import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'analytics_page.dart';
import 'calendar_page.dart';
import 'subjects_page.dart';
import 'today_page.dart';

/// Bottom-tab shell.
///
/// Tabs are held in an [IndexedStack] so each keeps its scroll position and
/// state while you move between them. Previously every destination called
/// `context.go('/today')` etc., which tore down and rebuilt the whole page —
/// scroll position was lost, the Hive stream re-subscribed, and there was no
/// transition at all.
///
/// The route still changes (so deep links and the back button behave), but the
/// pages themselves are no longer rebuilt from scratch.
class HomeShell extends StatefulWidget {
  final int tab;
  const HomeShell({super.key, required this.tab});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _routes = ['/today', '/subjects', '/calendar', '/analytics'];

  // Built lazily: an unvisited tab costs nothing until it's first opened.
  final _built = <int, Widget>{};

  Widget _page(int i) => _built.putIfAbsent(
        i,
        () => switch (i) {
          0 => const TodayPage(),
          1 => const SubjectsPage(),
          2 => const CalendarPage(),
          _ => const AnalyticsPage(),
        },
      );

  void _select(int i) {
    if (i == widget.tab) return;
    HapticFeedback.selectionClick();
    context.go(_routes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: widget.tab,
          children: [for (var i = 0; i < 4; i++) _page(i)],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: widget.tab,
            onDestinationSelected: _select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.wb_sunny_outlined),
                selectedIcon: Icon(Icons.wb_sunny_rounded),
                label: 'Today',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Subjects',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                selectedIcon: Icon(Icons.calendar_month_rounded),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Progress',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
