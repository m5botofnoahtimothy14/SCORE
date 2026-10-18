import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teachcross_mobile/core/layout/responsive.dart';
import 'package:teachcross_mobile/core/models/identity.dart';
import 'package:teachcross_mobile/core/theme/app_theme.dart';

/// Pumps [child] at a fixed window size, the way a phone, tablet or desktop
/// window would deliver it.
Future<void> pumpAt(
  WidgetTester tester,
  Size size,
  Widget child, {
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: child,
    ),
  );
}

Widget _host(BuildContext context, Widget child) => Scaffold(body: child);

void main() {
  group('breakpoints', () {
    testWidgets('classify widths', (tester) async {
      late bool phone, tablet, large;
      late int columns;

      await pumpAt(tester, const Size(400, 800), Builder(builder: (context) {
        phone = isPhone(context);
        tablet = isTablet(context);
        large = isLarge(context);
        columns = columnsFor(context);
        return const SizedBox();
      }));

      expect(phone, isTrue);
      expect(tablet, isFalse);
      expect(large, isFalse);
      expect(columns, 1);

      await pumpAt(tester, const Size(800, 1000), Builder(builder: (context) {
        phone = isPhone(context);
        tablet = isTablet(context);
        large = isLarge(context);
        columns = columnsFor(context);
        return const SizedBox();
      }));

      expect(phone, isFalse);
      expect(tablet, isTrue);
      expect(large, isFalse);
      expect(columns, 2);

      await pumpAt(tester, const Size(1280, 900), Builder(builder: (context) {
        phone = isPhone(context);
        tablet = isTablet(context);
        large = isLarge(context);
        columns = columnsFor(context);
        return const SizedBox();
      }));

      expect(phone, isFalse);
      expect(tablet, isFalse);
      expect(large, isTrue);
      expect(columns, 3);
    });

    testWidgets('columnsFor honours min, max and item count', (tester) async {
      late int two;
      late int capped;

      await pumpAt(tester, const Size(400, 800), Builder(builder: (context) {
        two = columnsFor(context, min: 2, itemCount: 2);
        capped = columnsFor(context, max: 2, itemCount: 5);
        return const SizedBox();
      }));

      expect(two, 2, reason: 'phone honours the floor so paired tiles stay paired');
      expect(capped, 1);

      await pumpAt(tester, const Size(1280, 900), Builder(builder: (context) {
        two = columnsFor(context, min: 2, itemCount: 2);
        capped = columnsFor(context, max: 2, itemCount: 5);
        return const SizedBox();
      }));

      expect(two, 2, reason: 'never more columns than tiles');
      expect(capped, 2);
    });
  });

  group('AdaptivePage', () {
    testWidgets('applies the phone gutter', (tester) async {
      final childKey = GlobalKey();
      await pumpAt(
        tester,
        const Size(400, 800),
        Builder(
          builder: (context) => _host(
            context,
            AdaptivePage(child: SizedBox(key: childKey, height: 10)),
          ),
        ),
      );
      // 400 - 2 * 16 gutter = 368 of content width.
      expect(tester.getSize(find.byKey(childKey)).width, 368);
      expect(tester.getRect(find.byKey(childKey)).left, 16);
    });

    testWidgets('caps and centres content on a large window', (tester) async {
      final childKey = GlobalKey();
      await pumpAt(
        tester,
        const Size(1600, 1000),
        Builder(
          builder: (context) => _host(
            context,
            AdaptivePage(
              center: true,
              child: SizedBox(key: childKey, height: 10),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byKey(childKey));
      expect(size.width, 1100 - 2 * kGutterLarge);
      // Centred: equal space either side of the capped column.
      final box = tester.getRect(find.byKey(childKey));
      expect(box.left, (1600 - box.width) / 2);
    });

    testWidgets('can opt out of centring', (tester) async {
      final childKey = GlobalKey();
      await pumpAt(
        tester,
        const Size(1600, 1000),
        Builder(
          builder: (context) => _host(
            context,
            AdaptivePage(center: false, child: SizedBox(key: childKey, height: 10)),
          ),
        ),
      );
      expect(tester.getRect(find.byKey(childKey)).left, kGutterLarge);
    });

    testWidgets('respects safe areas when asked', (tester) async {
      final childKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(builder: (context) {
            return MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(top: 47)),
              child: Scaffold(
                body: AdaptivePage(
                  respectTopSafeArea: true,
                  child: SizedBox(key: childKey, height: 10),
                ),
              ),
            );
          }),
        ),
      );
      expect(tester.getRect(find.byKey(childKey)).top, 47);
    });
  });

  group('AdaptiveGrid', () {
    Widget gridHost(int count) => Builder(
          builder: (context) => _host(
            context,
            ListView(
              children: [
                AdaptiveGrid(
                  itemExtent: 100,
                  children: [for (var i = 0; i < count; i++) const SizedBox.expand()],
                ),
              ],
            ),
          ),
        );

    testWidgets('reflows by width and never squashes tiles', (tester) async {
      await pumpAt(tester, const Size(400, 900), gridHost(4));
      var height = tester.getSize(find.byType(AdaptiveGrid)).height;
      // One column: 4 rows of 100 with 12px gaps.
      expect(height, 4 * 100 + 3 * 12);

      await pumpAt(tester, const Size(800, 900), gridHost(4));
      height = tester.getSize(find.byType(AdaptiveGrid)).height;
      expect(height, 2 * 100 + 12);

      await pumpAt(tester, const Size(1280, 900), gridHost(4));
      height = tester.getSize(find.byType(AdaptiveGrid)).height;
      expect(height, 2 * 100 + 12, reason: 'four items never stretch past three columns');
    });

    testWidgets('grows tile height with text scale instead of clipping', (tester) async {
      await pumpAt(tester, const Size(400, 900), gridHost(2));
      final normal = tester.getSize(find.byType(AdaptiveGrid)).height;

      await pumpAt(tester, const Size(400, 900), gridHost(2), textScale: 1.6);
      final scaled = tester.getSize(find.byType(AdaptiveGrid)).height;

      expect(scaled, greaterThan(normal));
      // 100 * (1 + 0.6 * 0.5) = 130 per tile, plus the 12px row gap.
      expect(scaled, 2 * 130 + 12);
    });

    testWidgets('is scrollable-free by default so it nests safely', (tester) async {
      await pumpAt(tester, const Size(400, 900), gridHost(3));
      final grid = tester.widget<GridView>(find.byType(GridView).last);
      expect(grid.shrinkWrap, isTrue);
      expect(grid.physics, isA<NeverScrollableScrollPhysics>());
      expect(grid.primary, isFalse);
    });

    testWidgets('renders nothing for an empty list', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 900),
        Builder(builder: (context) => _host(context, const AdaptiveGrid(children: []))),
      );
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('real metric tiles do not overflow at any width or text scale', (tester) async {
      for (final size in [const Size(360, 800), const Size(834, 1000), const Size(1400, 900)]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          await pumpAt(
            tester,
            size,
            Builder(
              builder: (context) => _host(
                context,
                ListView(
                  children: [
                    AdaptiveGrid(
                      minColumns: 2,
                      itemExtent: 142,
                      spacing: 10,
                      children: [
                        MetricTile(
                          icon: Icons.mark_chat_unread_outlined,
                          label: 'Unread messages',
                          value: '128',
                          accent: TierAccent.of(AppTier.student),
                        ),
                        MetricTile(
                          icon: Icons.insights_outlined,
                          label: 'Failed notifications',
                          value: '—',
                          accent: TierAccent.of(AppTier.student),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            textScale: scale,
          );
          expect(tester.takeException(), isNull, reason: 'overflow at $size scale $scale');
        }
      }
    });

    testWidgets('home action cards keep their height and never clip', (tester) async {
      const actions = [
        (Icons.groups_outlined, 'My class', 'Teachers & class info'),
        (Icons.forum_outlined, 'Messages', 'Talk to your teachers'),
        (Icons.apartment_outlined, 'School leadership', 'Contact the leadership'),
      ];

      for (final size in [const Size(360, 800), const Size(834, 1000), const Size(1400, 900)]) {
        await pumpAt(
          tester,
          size,
          Builder(
            builder: (context) => _host(
              context,
              ListView(
                children: [
                  AdaptiveGrid(
                    maxColumns: 2,
                    itemExtent: 76,
                    spacing: 8,
                    children: [
                      for (final a in actions)
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: SizedBox(width: 38, height: 38, child: Icon(a.$1)),
                            title: Text(a.$2),
                            subtitle: Text(a.$3),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'overflow at $size');

        // Stacked on a phone, two-up from tablet width on.
        final rows = size.width < kCompactMaxWidth ? 3 : 2;
        expect(
          tester.getSize(find.byType(AdaptiveGrid)).height,
          rows * 76 + (rows - 1) * 8,
        );
      }
    });
  });
}