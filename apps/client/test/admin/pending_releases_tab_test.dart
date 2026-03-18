import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/tabs/pending_releases_tab.dart';

import '../support/fake_admin_dashboard_delegate.dart';

void main() {
  testWidgets('Pending releases tab exposes completion email and message artist actions', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      pendingReleases: const [
        {
          'id': 15,
          'artist_id': 9,
          'artist_name': 'Maya Waves',
          'artist_email': 'maya@example.com',
          'release_title': 'Ocean Lights',
          'status': 'pending',
          'created_at': '2026-03-18T10:00:00Z',
          'artist_data': <String, dynamic>{},
          'release_data': <String, dynamic>{},
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingReleasesTab(delegate: delegate),
        ),
      ),
    );

    await tester.tap(find.text('Maya Waves'));
    await tester.pumpAndSettle();

    expect(find.text('Send completion email'), findsOneWidget);
    expect(find.text('Message artist'), findsOneWidget);

    await tester.tap(find.text('Send completion email'));
    await tester.pump();

    expect(delegate.remindedPendingReleaseId, 15);
    expect(delegate.remindedArtistName, 'Maya Waves');

    await tester.tap(find.text('Message artist'));
    await tester.pump();

    expect(delegate.messagedPendingRelease?['id'], 15);
    expect(delegate.messagedPendingRelease?['artist_email'], 'maya@example.com');
  });

  testWidgets('Pending releases message action is disabled when artist email is missing', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      pendingReleases: const [
        {
          'id': 16,
          'artist_name': 'No Email Artist',
          'artist_email': '',
          'release_title': 'Untitled',
          'status': 'pending',
          'created_at': '2026-03-18T10:00:00Z',
          'artist_data': <String, dynamic>{},
          'release_data': <String, dynamic>{},
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingReleasesTab(delegate: delegate),
        ),
      ),
    );

    await tester.tap(find.text('No Email Artist'));
    await tester.pumpAndSettle();

    final messageButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Message artist'),
    );

    expect(messageButton.onPressed, isNull);
  });
}
