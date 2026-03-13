import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:artist_portal/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ArtistPortalApp());
    await tester.pump();
    // Either loading indicator or login/dashboard is shown
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
