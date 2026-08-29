import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/pages/create_subject_page.dart';
import '../../presentation/pages/create_topic_page.dart';
import '../../presentation/pages/home_shell.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/splash_page.dart';
import '../../presentation/pages/subject_detail_page.dart';
import '../../presentation/pages/topic_detail_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),

      GoRoute(path: '/today',     builder: (_, __) => const HomeShell(tab: 0)),
      GoRoute(path: '/subjects',  builder: (_, __) => const HomeShell(tab: 1)),
      GoRoute(path: '/calendar',  builder: (_, __) => const HomeShell(tab: 2)),
      GoRoute(path: '/analytics', builder: (_, __) => const HomeShell(tab: 3)),
      GoRoute(path: '/settings',  builder: (_, __) => const SettingsPage()),

      GoRoute(
        path: '/topic/:id',
        builder: (_, s) => TopicDetailPage(topicId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/subject/:id',
        builder: (_, s) => SubjectDetailPage(subjectId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/create/topic',
        builder: (_, s) => CreateTopicPage(
            initialSubjectId: s.uri.queryParameters['subjectId']),
      ),
      GoRoute(
        path: '/create/subject',
        builder: (_, __) => const CreateSubjectPage(),
      ),
      GoRoute(
        path: '/edit/subject/:id',
        builder: (_, s) =>
            CreateSubjectPage(editId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/edit/topic/:id',
        builder: (_, s) => CreateTopicPage(editId: s.pathParameters['id']),
      ),
    ],
    errorBuilder: (_, s) => Scaffold(
      body: Center(child: Text('Route not found: ${s.uri}')),
    ),
  );
});
