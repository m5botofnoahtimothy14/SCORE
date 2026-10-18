import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:teachcross_mobile/core/config/router.dart';
import 'package:teachcross_mobile/core/models/identity.dart';
import 'package:teachcross_mobile/core/providers/identity_provider.dart';
import 'package:teachcross_mobile/core/theme/app_theme.dart';

AppIdentity _identity(AppTier tier) => AppIdentity(
      userId: 'u1',
      displayName: 'Test User',
      role: tier == AppTier.student ? 'student' : (tier == AppTier.teacher ? 'teacher' : 'principal'),
      tier: tier,
      schoolId: 's1',
      schoolName: 'Test School',
      classIds: tier == AppTier.student ? const [] : const ['c1'],
      teacherId: tier == AppTier.student ? null : 't1',
    );

/// Boots the real [AppShell] around a stub route at a fixed window size.
Future<GoRouter> _bootShell(
  WidgetTester tester,
  AppTier tier, {
  required Size size,
  String location = '/home',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const _Stub()),
          GoRoute(path: '/my-class', builder: (_, __) => const _Stub()),
          GoRoute(path: '/conversations', builder: (_, __) => const _Stub()),
          GoRoute(
            path: '/conversations/:id',
            builder: (_, __) => const _Stub(),
          ),
          GoRoute(path: '/announcements', builder: (_, __) => const _Stub()),
          GoRoute(path: '/profile', builder: (_, __) => const _Stub()),
          GoRoute(path: '/my-students', builder: (_, __) => const _Stub()),
          GoRoute(path: '/support-queue', builder: (_, __) => const _Stub()),
          GoRoute(path: '/insights', builder: (_, __) => const _Stub()),
          GoRoute(path: '/staff', builder: (_, __) => const _Stub()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        identityProvider.overrideWith((ref) async => _identity(tier)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _Stub extends StatelessWidget {
  const _Stub();
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

void main() {
  group('role destinations are unchanged', () {
    test('student sees exactly the student surface', () {
      expect(
        destinationsFor(AppTier.student).map((d) => d.label),
        ['Home', 'My Class', 'Messages', 'Notices', 'Profile'],
      );
      expect(
        destinationsFor(AppTier.student).map((d) => d.route),
        ['/home', '/my-class', '/conversations', '/announcements', '/profile'],
      );
    });

    test('teacher never sees school-wide management', () {
      final routes = destinationsFor(AppTier.teacher).map((d) => d.route).toList();
      expect(routes, ['/home', '/my-students', '/support-queue', '/announcements', '/profile']);
      expect(routes, isNot(contains('/staff')));
      expect(routes, isNot(contains('/insights')));
    });

    test('leadership sees staff and insights', () {
      expect(
        destinationsFor(AppTier.leadership).map((d) => d.label),
        ['Home', 'Insights', 'Staff', 'Notices', 'Profile'],
      );
    });
  });

  group('route guard', () {
    test('students cannot open staff or leadership surfaces', () {
      expect(canAccessRoute(AppTier.student, '/staff'), isFalse);
      expect(canAccessRoute(AppTier.student, '/insights'), isFalse);
      expect(canAccessRoute(AppTier.student, '/my-students'), isFalse);
      expect(canAccessRoute(AppTier.student, '/conversations'), isTrue);
    });

    test('teachers are blocked from leadership-only surfaces', () {
      expect(canAccessRoute(AppTier.teacher, '/staff'), isFalse);
      expect(canAccessRoute(AppTier.teacher, '/insights'), isFalse);
      expect(canAccessRoute(AppTier.teacher, '/support-queue'), isTrue);
    });

    test('leadership can open everything', () {
      expect(canAccessRoute(AppTier.leadership, '/staff'), isTrue);
      expect(canAccessRoute(AppTier.leadership, '/insights'), isTrue);
      expect(canAccessRoute(AppTier.leadership, '/support-queue'), isTrue);
    });
  });

  group('AppShell navigation adapts', () {
    testWidgets('phone keeps the bottom navigation bar', (tester) async {
      await _bootShell(tester, AppTier.student, size: const Size(400, 800));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('My Class'), findsOneWidget);
    });

    testWidgets('tablet swaps to a side rail with the same destinations',
        (tester) async {
      await _bootShell(tester, AppTier.student, size: const Size(820, 1180));

      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse, reason: 'a tablet keeps the compact rail');
      expect(
        rail.destinations.map((d) => (d.label as Text).data),
        ['Home', 'My Class', 'Messages', 'Notices', 'Profile'],
      );
    });

    testWidgets('large screens extend the rail', (tester) async {
      await _bootShell(tester, AppTier.leadership, size: const Size(1440, 900));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(rail.selectedIndex, 0);
      expect(
        rail.destinations.map((d) => (d.label as Text).data),
        ['Home', 'Insights', 'Staff', 'Notices', 'Profile'],
      );
    });

    testWidgets('rail index still maps nested routes to Messages', (tester) async {
      await _bootShell(
        tester,
        AppTier.student,
        size: const Size(820, 1180),
        location: '/conversations/abc123',
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
    });

    testWidgets('bottom bar index still maps nested routes to Messages', (tester) async {
      await _bootShell(
        tester,
        AppTier.student,
        size: const Size(400, 800),
        location: '/conversations/abc123',
      );

      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
    });

    testWidgets('tapping a rail destination navigates', (tester) async {
      final router =
          await _bootShell(tester, AppTier.teacher, size: const Size(820, 1180));

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.inbox_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, '/support-queue');
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
        2,
      );
    });

    testWidgets('resizing from phone to tablet swaps bar for rail in place',
        (tester) async {
      await _bootShell(tester, AppTier.student, size: const Size(400, 800));
      expect(find.byType(NavigationBar), findsOneWidget);

      tester.view.physicalSize = const Size(900, 700);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('a short landscape window does not overflow the rail', (tester) async {
      await _bootShell(tester, AppTier.leadership, size: const Size(1200, 300));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}