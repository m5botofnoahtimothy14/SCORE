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
          GoRoute(path: '/mentor-desk', builder: (_, __) => const _Stub()),
          GoRoute(path: '/mentor-desk/doubt/:id', builder: (_, __) => const _Stub()),
          GoRoute(path: '/announcements', builder: (_, __) => const _Stub()),
          GoRoute(path: '/profile', builder: (_, __) => const _Stub()),
          GoRoute(path: '/mentor-desk/queue', builder: (_, __) => const _Stub()),
          GoRoute(path: '/mentor-desk/availability', builder: (_, __) => const _Stub()),
          GoRoute(path: '/mentor-desk/slt', builder: (_, __) => const _Stub()),
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
        ['Mentor Desk', 'Notices', 'Profile'],
      );
      expect(
        destinationsFor(AppTier.student).map((d) => d.route),
        ['/mentor-desk', '/announcements', '/profile'],
      );
    });

    test('teacher sees mentor desk surfaces only', () {
      final routes = destinationsFor(AppTier.teacher).map((d) => d.route).toList();
      expect(routes, ['/mentor-desk/queue', '/mentor-desk/availability', '/announcements', '/profile']);
      expect(routes, isNot(contains('/staff')));
      expect(routes, isNot(contains('/insights')));
    });

    test('leadership sees oversight and notices', () {
      expect(
        destinationsFor(AppTier.leadership).map((d) => d.label),
        ['Oversight', 'Notices', 'Profile'],
      );
    });
  });

  group('route guard', () {
    test('students cannot open mentor or leadership surfaces', () {
      expect(canAccessRoute(AppTier.student, '/mentor-desk/slt'), isFalse);
      expect(canAccessRoute(AppTier.student, '/mentor-desk/queue'), isFalse);
      expect(canAccessRoute(AppTier.student, '/mentor-desk/availability'), isFalse);
      expect(canAccessRoute(AppTier.student, '/mentor-desk'), isTrue);
    });

    test('teachers are blocked from leadership-only surfaces', () {
      expect(canAccessRoute(AppTier.teacher, '/mentor-desk/slt'), isFalse);
      expect(canAccessRoute(AppTier.teacher, '/mentor-desk/queue'), isTrue);
    });

    test('leadership can open everything', () {
      expect(canAccessRoute(AppTier.leadership, '/mentor-desk/slt'), isTrue);
      expect(canAccessRoute(AppTier.leadership, '/mentor-desk/queue'), isTrue);
      expect(canAccessRoute(AppTier.leadership, '/announcements'), isTrue);
    });
  });

  group('AppShell navigation adapts', () {
    testWidgets('phone keeps the bottom navigation bar', (tester) async {
      await _bootShell(tester, AppTier.student, size: const Size(400, 800));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Mentor Desk'), findsOneWidget);
    });

    testWidgets('tablet swaps to a side rail with the same destinations',
        (tester) async {
      await _bootShell(tester, AppTier.student, size: const Size(820, 1180));

      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse, reason: 'a tablet keeps the compact rail');
      expect(
        rail.destinations.map((d) => (d.label as Text).data),
        ['Mentor Desk', 'Notices', 'Profile'],
      );
    });

    testWidgets('large screens extend the rail', (tester) async {
      await _bootShell(tester, AppTier.leadership, size: const Size(1440, 900));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(rail.selectedIndex, 0);
      expect(
        rail.destinations.map((d) => (d.label as Text).data),
        ['Oversight', 'Notices', 'Profile'],
      );
    });

    testWidgets('rail index still maps nested routes to Mentor Desk', (tester) async {
      await _bootShell(
        tester,
        AppTier.student,
        size: const Size(820, 1180),
        location: '/mentor-desk/doubt/abc123',
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 0);
    });

    testWidgets('bottom bar index still maps nested routes to Mentor Desk', (tester) async {
      await _bootShell(
        tester,
        AppTier.student,
        size: const Size(400, 800),
        location: '/mentor-desk/doubt/abc123',
      );

      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
    });

    testWidgets('tapping a rail destination navigates', (tester) async {
      final router =
          await _bootShell(tester, AppTier.teacher, size: const Size(820, 1180));

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.accessibility_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, '/mentor-desk/availability');
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
        1,
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
