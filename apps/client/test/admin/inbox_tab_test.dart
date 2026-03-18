import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/tabs/inbox_tab.dart';

import '../support/fake_admin_dashboard_delegate.dart';

void main() {
  testWidgets('Inbox tab exposes delete action and opens selected thread', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      inboxThreads: const [
        {
          'id': 7,
          'artist_name': 'Maya Waves',
          'last_message_preview': 'Can we update the release date?',
          'has_label_reply': false,
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InboxTab(delegate: delegate),
        ),
      ),
    );

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(delegate.deletedThreadId, 7);
    expect(delegate.deletedArtistName, 'Maya Waves');

    await tester.tap(find.text('Maya Waves'));
    await tester.pump();

    expect(delegate.openedThreadId, 7);
  });
}
