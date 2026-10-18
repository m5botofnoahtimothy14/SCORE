// First-boot EULA gate: versioned persistence, the routing guard, and the two
// modes of the terms screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:teachcross_mobile/core/config/app_config.dart';
import 'package:teachcross_mobile/core/config/router.dart';
import 'package:teachcross_mobile/core/legal/eula_gate.dart';
import 'package:teachcross_mobile/core/theme/app_theme.dart';
import 'package:teachcross_mobile/core/widgets/developer_signature.dart';
import 'package:teachcross_mobile/features/legal/screens/eula_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EulaStore.debugReset();
  });

  /// Simulates a cold launch: forget the in-memory cache, read the store again.
  Future<void> coldLaunch() async {
    EulaStore.debugReset();
    await EulaStore.load();
  }

  group('EulaStore', () {
    test('a fresh install has not accepted anything', () async {
      await coldLaunch();
      expect(EulaStore.isLoaded, isTrue);
      expect(EulaStore.isAccepted, isFalse);
    });

    test('accepting persists the version and a readable date', () async {
      await coldLaunch();
      await EulaStore.accept(userId: 'u1');

      expect(EulaStore.isAccepted, isTrue);
      expect(EulaStore.acceptedVersion, EulaStore.version);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('eula_accepted_version'), EulaStore.version);
      expect(EulaStore.acceptedAt, isNotNull);
      expect(EulaStore.acceptedOnLabel(), matches(r'^\d{1,2} \w+ \d{4}$'));
    });

    test('acceptance survives a restart so it is asked only once', () async {
      await coldLaunch();
      await EulaStore.accept();

      // Simulate the next cold launch: only the persisted store remains.
      await coldLaunch();
      expect(EulaStore.isAccepted, isTrue);
    });

    test('a changed version asks again', () async {
      SharedPreferences.setMockInitialValues({
        'eula_accepted_version': '2020-01-01',
        'eula_accepted_at': '2020-01-01T09:00:00.000',
      });
      await coldLaunch();

      expect(EulaStore.acceptedVersion, '2020-01-01');
      expect(EulaStore.isAccepted, isFalse, reason: 'old terms must be re-read');
    });
  });

  group('EulaGate guard', () {
    test('blocks the app until consent is given', () async {
      await coldLaunch();
      expect(EulaGate.isBlocking, isTrue);
      expect(EulaGate.guard('/home'), '/legal/eula');
      expect(EulaGate.guard('/conversations'), '/legal/eula');
      expect(EulaGate.guard('/auth/school-select'), '/legal/eula');
    });

    test('leaves the splash and the legal screens reachable', () async {
      await coldLaunch();
      expect(EulaGate.guard('/'), isNull);
      expect(EulaGate.guard('/legal/eula'), isNull);
      expect(EulaGate.guard('/legal/declined'), isNull);
    });

    test('stops blocking once the current version is accepted', () async {
      await coldLaunch();
      await EulaStore.accept();
      expect(EulaGate.guard('/home'), isNull);
      expect(EulaGate.guard('/conversations'), isNull);
    });
  });

  group('redirect policy (consent gate first, then auth)', () {
    Future<String?> resolve(
      String location, {
      bool signedIn = false,
      bool anonymous = false,
      bool onboarded = false,
    }) =>
        resolveRedirect(
          location: location,
          signedIn: signedIn,
          anonymous: anonymous,
          isOnboarded: () async => onboarded,
        );

    test('first boot lands on the terms, not on the app', () async {
      await coldLaunch();
      expect(await resolve('/'), isNull, reason: 'the splash must play');
      expect(await resolve('/auth/school-select'), '/legal/eula');
    });

    test('an anonymous visitor can actually reach the terms', () async {
      await coldLaunch();
      // The auth gate must not bounce the consent screen back to school
      // selection, which would redirect straight back here: a dead loop.
      expect(await resolve('/legal/eula'), isNull);
      expect(await resolve('/legal/declined'), isNull);
    });

    test('accepting releases every gate in one step', () async {
      await coldLaunch();
      await EulaStore.accept();
      expect(await resolve('/'), isNull, reason: 'the splash still plays');
      expect(await resolve('/auth/school-select'), isNull,
          reason: 'sign-up is open again');
      expect(await resolve('/home'), '/auth/school-select',
          reason: 'but the app still needs a session');
    });

    test('signed-in users are sent from auth routes into the app', () async {
      await coldLaunch();
      await EulaStore.accept();
      expect(await resolve('/auth/school-select', signedIn: true), '/home');
      expect(await resolve('/legal/eula', signedIn: true), isNull);
    });

    test('the existing auth guard is unchanged once terms are accepted',
        () async {
      await coldLaunch();
      await EulaStore.accept();

      expect(await resolve('/home'), '/auth/school-select');
      expect(
        await resolve('/home', signedIn: true, anonymous: true),
        '/auth/school-select',
        reason: 'an anonymous session with no membership must fail closed',
      );
      expect(
        await resolve('/home', signedIn: true, anonymous: true, onboarded: true),
        isNull,
      );
      expect(
        await resolve('/auth/school-select', signedIn: true, anonymous: true),
        isNull,
        reason: 'the activation flow stays reachable for anonymous users',
      );
    });

    test('an unsigned-in activation flow is never gated by consent again',
        () async {
      await coldLaunch();
      await EulaStore.accept();
      expect(await resolve('/auth/student-enroll'), isNull);
      expect(await resolve('/auth/teacher-enroll'), isNull);
    });
  });

  group('EulaScreen', () {
    // The agreement is longer than the viewport on purpose, so every
    // assertion scrolls to its target and aligns it before tapping.
    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.dragUntilVisible(
        finder,
        find.byType(ListView),
        const Offset(0, -300),
        maxIteration: 400,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('renders every clause and the signature', (tester) async {
      await tester.pumpWidget(_app(const EulaScreen()));
      await tester.pump();

      expect(find.text(kEulaTitle), findsOneWidget);
      expect(find.text('Effective date: $kEulaEffectiveDate'), findsOneWidget);

      for (final section in kEulaSections) {
        await scrollTo(tester, find.text(section.heading));
        expect(find.text(section.heading), findsOneWidget,
            reason: 'clause ${section.number} must be present');
      }

      await scrollTo(tester, find.byType(DeveloperSignature));
      expect(find.text(AppConfig.signatureLine), findsWidgets);
    });

    testWidgets('consent starts unticked and accept is disabled', (tester) async {
      await tester.pumpWidget(_app(const EulaScreen()));
      await tester.pump();

      await scrollTo(tester, find.byType(Checkbox));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      final accept = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Accept and continue'),
      );
      expect(accept.onPressed, isNull);
    });

    testWidgets('ticking the box enables accept, which records consent',
        (tester) async {
      var accepted = false;
      await tester.pumpWidget(_app(EulaScreen(onAccepted: (context) async {
        accepted = true;
      })));
      await tester.pump();

      await scrollTo(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final accept = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Accept and continue'),
      );
      expect(accept.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Accept and continue'));
      await tester.pump();
      expect(accepted, isTrue);
    });

    testWidgets('declining is confirmed and then reported', (tester) async {
      var declined = false;
      await tester.pumpWidget(_app(EulaScreen(onDeclined: (context) async {
        declined = true;
      })));
      await tester.pump();

      await scrollTo(tester, find.widgetWithText(OutlinedButton, 'Decline'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(find.text('Decline the terms?'), findsOneWidget);
      expect(find.textContaining('cannot be used without accepting'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Decline'));
      await tester.pumpAndSettle();
      expect(declined, isTrue);
    });

    testWidgets('accepted mode is read-only and shows the acceptance date',
        (tester) async {
      await coldLaunch();
      await EulaStore.accept();

      await tester.pumpWidget(_app(const EulaScreen(acceptedMode: true)));
      await tester.pump();

      await scrollTo(tester, find.textContaining('You accepted these on'));
      expect(find.textContaining(EulaStore.acceptedOnLabel()), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Accept and continue'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Decline'), findsNothing);
    });
  });

  group('DeveloperSignature', () {
    testWidgets('shows the lockup, the developer and both contacts',
        (tester) async {
      await tester.pumpWidget(_app(const DeveloperSignature()));

      expect(find.text('CRIMSON X NOAH TIMOTHY KEBA'), findsOneWidget);
      expect(find.text('Developed by Noah Timothy Keba Joseph'), findsOneWidget);
      expect(find.text('support@teachcross.app'), findsOneWidget);
      expect(find.text('+91 90000 00000'), findsOneWidget);
    });
  });
}

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );
