// Basic Flutter widget test for LabelOps app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:labelops_client/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const LabelOpsApp());
    await tester.pumpAndSettle();
    // App should show login or dashboard.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
