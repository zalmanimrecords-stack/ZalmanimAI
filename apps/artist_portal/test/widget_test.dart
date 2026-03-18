import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:artist_portal/features/legal/cookie_consent_page.dart';

void main() {
  testWidgets('Cookie consent page smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CookieConsentPage(
          onAccept: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Cookie & consent'), findsOneWidget);
  });
}
