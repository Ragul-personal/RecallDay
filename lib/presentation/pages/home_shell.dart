import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'today_page.dart';
import 'subjects_page.dart';
import 'calendar_page.dart';
import 'analytics_page.dart';

class HomeShell extends StatelessWidget {
  final int tab;
  const HomeShell({super.key, required this.tab});

  @override
  Widget build(BuildContext context) {
    final pages = const [TodayPage(), SubjectsPage(), CalendarPage(), AnalyticsPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/today'); break;
            case 1: context.go('/subjects'); break;
            case 2: context.go('/calendar'); break;
            case 3: context.go('/analytics'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.bookmarks_outlined), selectedIcon: Icon(Icons.bookmarks), label: 'Subjects'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Analytics'),
        ],
      ),
    );
  }
}
