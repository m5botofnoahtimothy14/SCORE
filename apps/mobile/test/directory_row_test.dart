// The teachers-directory row must always read horizontally.
//
// This is a regression test: the row once squeezed the name into a
// single-character column, so the teacher's name was unreadable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teachcross_mobile/core/theme/app_theme.dart';
import 'package:teachcross_mobile/features/directory/screens/teacher_directory_row.dart';

Widget _app(Widget child, {double width = 360}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  final teacher = <String, dynamic>{
    'id': 't1',
    'first_name': 'Rahul',
    'last_name': 'Verma',
    'is_leadership': true,
    'last_seen_at': DateTime.now().toIso8601String(),
  };

  testWidgets('the name reads horizontally, not one letter per line',
      (tester) async {
    await tester.pumpWidget(_app(
      TeacherDirectoryRow(
        teacher: teacher,
        isStudent: true,
        opening: false,
        onMessage: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rahul Verma'), findsOneWidget);

    // The name must be wider than a single character.
    final box = tester.getRect(find.text('Rahul Verma'));
    expect(box.width, greaterThan(60),
        reason: 'the name was squeezed into a single-character column');
    expect(box.height, lessThan(40),
        reason: 'the name wrapped over many lines');
  });

  testWidgets('a long name is ellipsised, not wrapped', (tester) async {
    await tester.pumpWidget(_app(
      TeacherDirectoryRow(
        teacher: <String, dynamic>{
          ...teacher,
          'first_name': 'Chandrasekharaswamy',
          'last_name': 'Venkataraman',
        },
        isStudent: true,
        opening: false,
        onMessage: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.text('Chandrasekharaswamy Venkataraman'));
    expect(box.height, lessThan(40));
  });

  testWidgets('the presence line and the leadership chip are visible',
      (tester) async {
    await tester.pumpWidget(_app(
      TeacherDirectoryRow(
        teacher: teacher,
        isStudent: true,
        opening: false,
        onMessage: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Leadership'), findsOneWidget);
    expect(find.textContaining('Online'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('a narrow phone still shows the name', (tester) async {
    await tester.pumpWidget(_app(
      TeacherDirectoryRow(
        teacher: teacher,
        isStudent: true,
        opening: false,
        onMessage: () {},
      ),
      width: 320,
    ));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.text('Rahul Verma'));
    expect(box.width, greaterThan(40));
  });
}
