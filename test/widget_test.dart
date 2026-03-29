// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eclassiut/features/home/home_screen.dart';
import 'package:eclassiut/models/models.dart';

void main() {
  testWidgets('App shows today schedule on Home', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          now: DateTime(2026, 03, 27, 10, 0),
          sessions: const <ClassSession>[],
          onOpenAttendance: (_, _, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current Lessons'), findsOneWidget);
    expect(find.text('All Lessons'), findsOneWidget);
    expect(find.text('No lessons today'), findsOneWidget);
    expect(find.text('No other lessons'), findsOneWidget);
  });
}
