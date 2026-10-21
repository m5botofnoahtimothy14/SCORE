// Splash sequence: the unified composition, the handoff guarantee and the
// reduce-motion path. The shine sweep loops, so these tests pump explicit
// durations instead of calling pumpAndSettle while the splash is on screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:teachcross_mobile/core/config/app_config.dart';
import 'package:teachcross_mobile/core/splash/splash_sequence.dart';
import 'package:teachcross_mobile/core/theme/app_theme.dart';

Future<GoRouter> _boot(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {  tester.view.devicePixelRatio = 1.0;
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

/// Advances the clock in small steps so every awaited continuation in the
/// splash (the animation, the boot sequence, the minimum-display wait) gets
/// a chance to run.
Future<void> _pumpPast(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the brand mark and the signature together on one screen',
      (tester) async {
    await _boot(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // One screen, not two: the mark and the lockup are visible at the same
    // time, on the same surface.
    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    expect(
      find.bySemanticsLabel(AppConfig.signatureLine),
      findsOneWidget,
      reason: 'the lockup must be announced as one phrase, not per glyph',
    );
    // The lockup is stacked: CRIMSON above the cross, the name below it.
    // In the animated path the name is drawn glyph by glyph, so the phrase
    // is asserted through the semantics label above; the plain-text form is
    // asserted in the reduce-motion test.
    expect(find.text(AppConfig.signatureTop), findsOneWidget);
    expect(find.text(AppConfig.signatureCross), findsOneWidget);
    expect(find.text('Developed by ${AppConfig.developerName}'), findsOneWidget);

    // Let the splash finish so its pending timer is cleared and the
    // looping shine sweep is disposed with it.
    await _pumpPast(tester, const Duration(milliseconds: 20000));
  });

  testWidgets('hands off to the school picker after the composition',
      (tester) async {
    final router = await _boot(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.school_rounded), findsOneWidget);

    // Past the minimum display time the navigation must have happened.
    await _pumpPast(tester, const Duration(milliseconds: 20000));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/auth/school-select',
    );
    expect(find.byIcon(Icons.school_rounded), findsNothing);
  });

  testWidgets('reduce motion shows the composition statically and still navigates',
      (tester) async {
    final router = await _boot(tester, disableAnimations: true);
    await tester.pump();

    // Nothing is animating: the whole composition is fully formed on the
    // first frame.
    expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    expect(find.text(AppConfig.signatureTop), findsOneWidget);
    expect(find.text(AppConfig.signatureName), findsOneWidget);

    await _pumpPast(tester, const Duration(milliseconds: 20000));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/auth/school-select',
    );
  });
}
