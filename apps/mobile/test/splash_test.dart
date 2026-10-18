// Splash sequence: the two panels, the handoff guarantee and the reduce-motion
// path. The shine sweep loops, so these tests pump explicit durations instead of
// calling pumpAndSettle while the splash is on screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:teachcross_mobile/core/config/app_config.dart';
import 'package:teachcross_mobile/core/splash/splash_sequence.dart';
import 'package:teachcross_mobile/core/theme/app_theme.dart';

Future<GoRouter> _boot(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashSequence()),
      GoRoute(path: '/home', builder: (_, __) => const _Stub('Home')),
      GoRoute(path: '/auth/school-select', builder: (_, __) => const _Stub('School')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  return router;
}

class _Stub extends StatelessWidget {
  final String label;
  const _Stub(this.label);
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

void main() {
  testWidgets('panel one shows the brand mark, then hands off to the app',
      (tester) async {
    final router = await _boot(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.school_rounded), findsOneWidget);

    // Past the last frame of the sequence the navigation must have happened.
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/auth/school-select',
    );
    expect(find.byIcon(Icons.school_rounded), findsNothing);
  });

  testWidgets('panel two shows the exact signature text', (tester) async {
    await _boot(tester);
    await tester.pump();
    // Halfway through panel two the lockup has fully faded in.
    await tester.pump(const Duration(milliseconds: 2400));

    expect(
      find.bySemanticsLabel(AppConfig.signatureLine),
      findsOneWidget,
      reason: 'the lockup must be announced as one phrase, not per glyph',
    );
    expect(find.text('Developed by ${AppConfig.developerName}'), findsOneWidget);
  });

  testWidgets('reduce motion shows both panels statically and still navigates',
      (tester) async {
    final router = await _boot(tester, disableAnimations: true);
    await tester.pump();

    // Nothing is animating: both panels are fully formed on the first frame.
    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    expect(find.text(AppConfig.signatureLine), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/auth/school-select',
    );
  });
}
