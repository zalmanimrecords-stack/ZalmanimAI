import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/tabs/artists_tab.dart';

import '../support/fake_admin_dashboard_delegate.dart';

void main() {
  testWidgets('Artists tab exposes Groover invite action', (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final delegate = FakeAdminDashboardDelegate();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistsTab(delegate: delegate),
        ),
      ),
    );

    expect(find.text('Groover invite'), findsOneWidget);

    await tester.tap(find.text('Groover invite'));
    await tester.pump();

    expect(delegate.grooverInviteDialogShown, isTrue);
  });
}
