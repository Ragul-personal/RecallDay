import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Persistent bottom-tab shell.
///
/// The scaffold — navigation bar and floating action button — is owned here
/// and stays mounted for the life of the session; only the branch body swaps.
///
/// Previously each tab was its own top-level route rebuilding a whole
/// `HomeShell`, so switching cross-faded the entire screen (the FAB visibly
/// popping in and out) and reset each page's scroll position. Each page also
/// carried its own FAB inside its body, so two different buttons animated
/// past each other during the change.
class HomeShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const HomeShell({super.key, required this.shell});

  void _select(int i) {
    if (i != shell.currentIndex) HapticFeedback.selectionClick();
    // initialLocation:true re-taps the current tab back to its root.
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // One FAB, owned by the shell, whose action follows the visible tab. Only
    // Today and Subjects have a primary create action; Calendar and Progress
    // are read-only, so it's simply absent there.
    final fab = switch (shell.currentIndex) {
      0 => _Fab(
          key: const ValueKey('fab-topic'),
          label: 'New topic',
          onPressed: () => context.push('/create/topic'),
        ),
      1 => _Fab(
          key: const ValueKey('fab-subject'),
          label: 'New subject',
          onPressed: () => context.push('/create/subject'),
        ),
      _ => null,
    };

    return Scaffold(
      body: SafeArea(bottom: false, child: shell),
      // Cross-fade between the two labels rather than letting one button
      // disappear and another appear.
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: fab ?? const SizedBox.shrink(key: ValueKey('fab-none')),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
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

class _Fab extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _Fab({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded),
      label: Text(label),
    );
  }
}
