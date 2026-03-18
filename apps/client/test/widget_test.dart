// Basic Flutter widget test for LabelOps app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:labelops_client/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'cookie_consent_given': true});
    await tester.pumpWidget(const LabelOpsApp());
    await tester.pump(const Duration(milliseconds: 200));
    // App should show login or dashboard.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
