import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/school_select_screen.dart';
import '../../features/auth/screens/student_enrollment_screen.dart';
import '../../features/auth/screens/teacher_enrollment_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/announcements/screens/announcements_screen.dart';
import '../../features/announcements/screens/announcement_detail_screen.dart';
import '../../features/announcements/screens/compose_announcement_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/auth/screens/account_states_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/profile/screens/notification_settings_screen.dart';
import '../../features/mentor_desk/screens/book_session_screen.dart';
import '../../features/mentor_desk/screens/doubt_conversation_screen.dart';
import '../../features/mentor_desk/screens/mentor_assessment_screen.dart';
import '../../features/mentor_desk/screens/mentor_availability_screen.dart';
import '../../features/mentor_desk/screens/mentor_queue_screen.dart';
import '../../features/mentor_desk/screens/mentor_session_detail_screen.dart';
import '../../features/mentor_desk/screens/rating_screen.dart';
import '../../features/mentor_desk/screens/session_detail_screen.dart';
import '../../features/mentor_desk/screens/slt_dashboard_screen.dart';
import '../../features/mentor_desk/screens/submit_doubt_screen.dart';
import '../../features/mentor_desk/screens/mentor_desk_home_screen.dart';
import '../../features/legal/screens/eula_screen.dart';
import '../../features/legal/screens/eula_declined_screen.dart';
import '../../core/models/identity.dart';
import '../../core/providers/identity_provider.dart';
import '../../core/legal/eula_gate.dart';
import '../../core/splash/splash_sequence.dart';
import '../../core/theme/app_theme.dart';
import '../layout/responsive.dart';
import '../notifications/notification_service.dart';

/// Maps a notification payload string to an in-app route, or null if unknown.
String? _routeForPayload(String payload) {
  if (payload.isEmpty) return null;
  if (payload == 'home') return '/home';
  if (payload.startsWith('conversation:')) {
    final id = payload.substring('conversation:'.length);
    return id.isEmpty ? '/mentor-desk' : '/mentor-desk/doubt/$id';
  }
  if (payload.startsWith('announcement:')) {
    final id = payload.substring('announcement:'.length);
    return id.isEmpty ? '/announcements' : '/announcements/$id';
  }
  return null;
}

/// Routes that only staff (mentor/leadership) may open.
const _staffOnlyPrefixes = <String>[
  '/mentor-desk/queue',
  '/mentor-desk/availability',
  '/mentor-desk/session/',
  '/mentor-desk/assessment',
];

/// Routes only leadership may open.
const _leadershipOnlyPrefixes = <String>['/mentor-desk/slt'];

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

Future<void> _acceptTerms(BuildContext context) async {
  String? userId;
  try {
    userId = Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    userId = null; // no session yet — the acceptance is still recorded locally
  }
  await EulaStore.accept(userId: userId);
  if (!context.mounted) return;
  context.go('/auth/school-select');
}

Future<void> _declineTerms(BuildContext context) async {
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {
    // Already signed out — the declined screen is shown either way.
  }
  invalidateOnboardingCache();
  if (!context.mounted) return;
  context.go('/legal/declined');
}

Future<String?> resolveRedirect({
  required String location,
  required bool signedIn,
  required bool anonymous,
  required Future<bool> Function() isOnboarded,
}) async {
  if (!EulaStore.isLoaded) await EulaStore.load();
  final consent = EulaGate.guard(location);
  if (consent != null) return consent;

  final isAuthRoute = location.startsWith('/auth');
  final isSplash = location == '/';
  final isOpenRoute = isSplash || isAuthRoute || location.startsWith('/legal');

  if (!signedIn) {
    return isOpenRoute ? null : '/auth/school-select';
  }

  if (anonymous && !await isOnboarded()) {
    return isOpenRoute ? null : '/auth/school-select';
  }

  if (isAuthRoute) {
    return '/home';
  }

  return null;
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
      return resolveRedirect(
        location: state.matchedLocation,
        signedIn: session != null,
        anonymous: session?.user.isAnonymous ?? false,
        isOnboarded: () async {
          if (session == null) return false;
          return _isOnboarded(session.user.id);
        },
      );
    },
    routes: [
      // Splash — the first route on every launch; it hands off to the gate.
      GoRoute(path: '/', builder: (_, __) => const SplashSequence()),

      // Legal
      GoRoute(
        path: '/legal/eula',
        builder: (_, __) => const EulaScreen(
          onAccepted: _acceptTerms,
          onDeclined: _declineTerms,
        ),
      ),
      GoRoute(path: '/legal/declined', builder: (_, __) => const EulaDeclinedScreen()),
      // Auth routes
      GoRoute(path: '/auth/school-select', builder: (_, __) => const SchoolSelectScreen()),
      GoRoute(path: '/auth/student-enroll', builder: (_, state) {
        final schoolId = state.uri.queryParameters['school_id'] ?? '';
        return StudentEnrollmentScreen(schoolId: schoolId);
      }),
      GoRoute(path: '/auth/teacher-enroll', builder: (_, state) {
        final schoolId = state.uri.queryParameters['school_id'] ?? '';
        return TeacherEnrollmentScreen(schoolId: schoolId);
      }),

      // Main app — shell route with role-aware navigation (bar or rail)
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/announcements', builder: (_, __) => const AnnouncementsScreen()),
          GoRoute(path: '/announcements/compose', builder: (_, __) => const ComposeAnnouncementScreen()),
          GoRoute(
            path: '/announcements/:id',
            builder: (_, state) => AnnouncementDetailScreen(
              announcementId: state.pathParameters['id']!,
            ),
          ),

          // Mentor Desk — student
          GoRoute(path: '/mentor-desk', builder: (_, __) => const MentorDeskHomeScreen()),
          GoRoute(path: '/mentor-desk/doubt/submit', builder: (_, __) => const SubmitDoubtScreen()),
          GoRoute(
            path: '/mentor-desk/doubt/:id',
            builder: (_, state) => MentorDoubtConversationScreen(requestId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/mentor-desk/session/book', builder: (_, __) => const BookSessionScreen()),
          GoRoute(
            path: '/mentor-desk/session/:id',
            builder: (_, state) => SessionDetailScreen(bookingId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/mentor-desk/rating/:id',
            builder: (_, state) => RatingScreen(requestId: state.pathParameters['id']!),
          ),

          // Mentor Desk — teacher/mentor
          GoRoute(path: '/mentor-desk/queue', builder: (_, __) => const MentorQueueScreen()),
          GoRoute(path: '/mentor-desk/availability', builder: (_, __) => const MentorAvailabilityScreen()),
          GoRoute(
            path: '/mentor-desk/session/:id/mentor',
            builder: (_, state) => MentorSessionDetailScreen(bookingId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/mentor-desk/assessment/:id',
            builder: (_, state) => MentorAssessmentScreen(requestId: state.pathParameters['id']!),
          ),

          // Mentor Desk — SLT oversight
          GoRoute(path: '/mentor-desk/slt', builder: (_, __) => const SLTDashboardScreen()),

          // Shared
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
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
          mainAxisSize: MainAxisSize.min,
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

/// One destination in the role-aware navigation (bottom bar or side rail).
class NavDest {
  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const NavDest(this.route, this.icon, this.activeIcon, this.label);
}

/// Navigation is role-specific: every tier lands on Mentor Desk first.
List<NavDest> destinationsFor(AppTier tier) => switch (tier) {
      AppTier.student => const [
          NavDest('/mentor-desk', Icons.support_agent_outlined, Icons.support_agent, 'Mentor Desk'),
          NavDest('/announcements', Icons.campaign_outlined, Icons.campaign, 'Notices'),
          NavDest('/profile', Icons.person_outline, Icons.person, 'Profile'),
        ],
      AppTier.teacher => const [
          NavDest('/mentor-desk/queue', Icons.list_outlined, Icons.list, 'Queue'),
          NavDest('/mentor-desk/availability', Icons.accessibility_outlined, Icons.accessibility, 'Availability'),
          NavDest('/announcements', Icons.campaign_outlined, Icons.campaign, 'Notices'),
          NavDest('/profile', Icons.person_outline, Icons.person, 'Profile'),
        ],
      AppTier.leadership => const [
          NavDest('/mentor-desk/slt', Icons.insights_outlined, Icons.insights, 'Oversight'),
          NavDest('/announcements', Icons.campaign_outlined, Icons.campaign, 'Notices'),
          NavDest('/profile', Icons.person_outline, Icons.person, 'Profile'),
        ],
    };

/// Shell with role-aware navigation: a bottom bar on phones, a side rail from
/// tablet width up.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);

    final identity = identityAsync.valueOrNull;
    if (identity == null) return Scaffold(body: child);

    final tier = identity.tier;
    final dests = destinationsFor(tier);
    final location = GoRouterState.of(context).matchedLocation;

    int index = dests.indexWhere((d) => _matches(d.route, location));
    if (index < 0) index = 0;

    void select(int i) {
      final target = dests[i].route;
      if (target != '/home' && !_canOpen(tier, target)) return;
      if (target == location) return;
      context.go(target);
    }

    final accent = TierAccent.of(tier);

    Widget selectedIconFor(NavDest d) => Container(
          decoration: BoxDecoration(
            color: accent.solid.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Icon(d.activeIcon),
        );

    if (!isPhone(context)) {
      final extended = isLarge(context);
      return Scaffold(
        body: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: NavigationRail(
                backgroundColor: Theme.of(context).colorScheme.surface,
                selectedIndex: index,
                extended: extended,
                minExtendedWidth: 200,
                groupAlignment: -1,
                scrollable: true,
                useIndicator: true,
                indicatorColor: accent.solid.withValues(alpha: 0.12),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                selectedLabelTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent.solid,
                ),
                unselectedLabelTextStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                destinations: [
                  for (final d in dests)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: selectedIconFor(d),
                      label: Text(d.label),
                    ),
                ],
                onDestinationSelected: select,
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: MediaQuery.of(context).padding.copyWith(
            bottom: MediaQuery.of(context).padding.bottom + 88,
          ),
        ),
        child: child,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: NavigationBar(
          selectedIndex: index,
          destinations: [
            for (final d in dests)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: selectedIconFor(d),
                label: d.label,
              ),
          ],
          onDestinationSelected: select,
        ),
      ),
    );
  }

  static bool _matches(String route, String location) {
    if (route == '/home') return location == '/home';
    return location == route || location.startsWith('$route/');
  }

  static bool _canOpen(AppTier tier, String path) {
    if (_leadershipOnlyPrefixes.any(path.startsWith)) {
      return tier == AppTier.leadership;
    }
    if (_staffOnlyPrefixes.any(path.startsWith)) {
      return tier != AppTier.student;
    }
    return true;
  }
}

bool canAccessRoute(AppTier tier, String path) =>
    AppShell._canOpen(tier, path);
