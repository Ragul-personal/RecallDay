import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/pages/analytics_page.dart';
import '../../presentation/pages/calendar_page.dart';
import '../../presentation/pages/create_subject_page.dart';
import '../../presentation/pages/create_topic_page.dart';
import '../../presentation/pages/home_shell.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/splash_page.dart';
import '../../presentation/pages/subject_detail_page.dart';
import '../../presentation/pages/subjects_page.dart';
import '../../presentation/pages/today_page.dart';
import '../../presentation/pages/topic_detail_page.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),

      // The four tabs live in a persistent shell.
      //
      // They used to be four separate top-level routes, each building its own
      // `HomeShell`. Switching tabs therefore replaced the whole route, so the
      // page transition cross-faded the entire screen — which is why the
      // "New subject" button appeared to pop in and vanish on every switch —
      // and every page was rebuilt from scratch, losing its scroll position.
      //
      // StatefulShellRoute keeps one shell alive with a navigator per branch,
      // so only the body swaps and the scaffold (nav bar and FAB) never
      // re-enters.
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/today', builder: (_, __) => const TodayPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/subjects',
                builder: (_, __) => const SubjectsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, __) => const CalendarPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                builder: (_, __) => const AnalyticsPage(),
              ),
            ],
          ),
        ],
      ),

      // Everything below is pushed above the shell (root navigator), so the
      // bottom navigation bar isn't visible on a detail or form screen.
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SettingsPage(),
      ),
      GoRoute(
        path: '/topic/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TopicDetailPage(topicId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/subject/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => SubjectDetailPage(subjectId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/create/topic',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CreateTopicPage(
          initialSubjectId: s.uri.queryParameters['subjectId'],
        ),
      ),
      GoRoute(
        path: '/create/subject',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CreateSubjectPage(),
      ),
      GoRoute(
        path: '/edit/subject/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CreateSubjectPage(editId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/edit/topic/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CreateTopicPage(editId: s.pathParameters['id']),
      ),
    ],
    errorBuilder: (_, s) => Scaffold(
      body: Center(child: Text('Route not found: ${s.uri}')),
    ),
  );
});
