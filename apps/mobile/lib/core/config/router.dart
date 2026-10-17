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
import '../notifications/notification_service.dart';

/// Maps a notification payload string to an in-app route, or null if unknown.
String? _routeForPayload(String payload) {
  if (payload.isEmpty) return null;
  if (payload == 'home') return '/home';
  if (payload.startsWith('conversation:')) {
    final id = payload.substring('conversation:'.length);
    return id.isEmpty ? '/conversations' : '/conversations/$id';
  }
  if (payload.startsWith('announcement:')) {
    final id = payload.substring('announcement:'.length);
    return id.isEmpty ? '/announcements' : '/announcements/$id';
  }
  return null;
}

/// Cache of whether an (anonymous) user has completed onboarding, i.e. holds
/// an active school membership. Avoids a DB round-trip on every navigation.
final Map<String, bool> _onboardedCache = {};

/// Call after a successful activation so the router re-evaluates onboarding.
void invalidateOnboardingCache([String? userId]) {
  if (userId == null) {
    _onboardedCache.clear();
  } else {
    _onboardedCache.remove(userId);
  }
}

Future<bool> _isOnboarded(String userId) async {
  final cached = _onboardedCache[userId];
  if (cached != null) return cached;
  try {
    final rows = await Supabase.instance.client
        .from('school_memberships')
        .select('id')
        .eq('user_id', userId)
        .eq('is_active', true)
        .limit(1);
    final ok = (rows as List).isNotEmpty;
    _onboardedCache[userId] = ok;
    return ok;
  } catch (_) {
    return false; // fail closed — keep the user on the auth flow
  }
}

/// Plain provider (no codegen) — avoids build_runner in CI/dev.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) async {
      final session = auth.currentSession;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (session == null) {
        return isAuthRoute ? null : '/auth/school-select';
      }

      // Anonymous sessions exist for the student/teacher activation flow.
      // They must not enter the app until activation grants a membership,
      // otherwise a failed activation strands the user inside /home.
      if (session.user.isAnonymous && !await _isOnboarded(session.user.id)) {
        return isAuthRoute ? null : '/auth/school-select';
      }

      if (isAuthRoute) {
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

  NotificationService.onNavigate = (payload) {
    final target = _routeForPayload(payload);
    if (target != null) router.go(target);
  };

  // Handle a notification that launched the app before the router existed.
  final pending = NotificationService.consumePendingNavigation();
  if (pending != null) {
    final target = _routeForPayload(pending);
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => router.go(target));
    }
  }

  return router;
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
