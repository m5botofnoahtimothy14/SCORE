import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/school_select_screen.dart';
import '../../features/auth/screens/student_enrollment_screen.dart';
import '../../features/auth/screens/teacher_enrollment_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/conversations/screens/conversation_list_screen.dart';
import '../../features/conversations/screens/conversation_screen.dart';
import '../../features/announcements/screens/announcements_screen.dart';
import '../../features/announcements/screens/announcement_detail_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/auth/screens/account_states_screen.dart';
import '../../features/directory/screens/directory_screen.dart';
import '../../features/directory/screens/leadership_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/profile/screens/notification_settings_screen.dart';

/// Plain provider (no codegen) — avoids build_runner in CI/dev.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      final session = auth.currentSession;
      final isLoggedIn = session != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) {
        return '/auth/school-select';
      }

      if (isLoggedIn && isAuthRoute) {
        return '/home';
      }

      return null;
    },
    routes: [
      // Auth routes
      GoRoute(path: '/', redirect: (_, __) => '/auth/school-select'),
      GoRoute(path: '/auth/school-select', builder: (_, __) => const SchoolSelectScreen()),
      GoRoute(path: '/auth/student-enroll', builder: (_, state) {
        final schoolId = state.uri.queryParameters['school_id'] ?? '';
        return StudentEnrollmentScreen(schoolId: schoolId);
      }),
      GoRoute(path: '/auth/teacher-enroll', builder: (_, state) {
        final schoolId = state.uri.queryParameters['school_id'] ?? '';
        return TeacherEnrollmentScreen(schoolId: schoolId);
      }),

      // Main app — shell route with bottom nav
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/conversations', builder: (_, __) => const ConversationListScreen()),
          GoRoute(
            path: '/conversations/:id',
            builder: (_, state) => ConversationScreen(
              conversationId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/announcements', builder: (_, __) => const AnnouncementsScreen()),
          GoRoute(
            path: '/announcements/:id',
            builder: (_, state) => AnnouncementDetailScreen(
              announcementId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/directory', builder: (_, __) => const DirectoryScreen()),
          GoRoute(path: '/leadership', builder: (_, __) => const LeadershipScreen()),
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
          GoRoute(path: '/notification-settings', builder: (_, __) => const NotificationSettingsScreen()),
        ],
      ),

      // Error states
      GoRoute(path: '/suspended', builder: (_, __) => const AccountSuspendedScreen()),
      GoRoute(path: '/access-denied', builder: (_, __) => const AccessDeniedScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page not found: ${state.error}'),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Shell with bottom navigation bar
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Messages'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Notices'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
        selectedIndex: _calculateSelectedIndex(context),
        onDestinationSelected: (index) => _onDestinationSelected(context, index),
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/conversations')) return 1;
    if (location.startsWith('/announcements')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/home'); break;
      case 1: context.go('/conversations'); break;
      case 2: context.go('/announcements'); break;
      case 3: context.go('/profile'); break;
    }
  }
}
