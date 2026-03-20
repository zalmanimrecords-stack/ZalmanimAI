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
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Send completion email'));
    await tester.pump();

    expect(delegate.remindedPendingReleaseId, 15);
    expect(delegate.remindedArtistName, 'Maya Waves');

    await tester.tap(find.text('Message artist'));
    await tester.pump();

    expect(delegate.messagedPendingRelease?['id'], 15);
    expect(delegate.messagedPendingRelease?['artist_email'], 'maya@example.com');
  });

  testWidgets('Pending releases remove dialog can archive an item', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      pendingReleases: const [
        {
          'id': 30,
          'artist_name': 'Archive Me',
          'artist_email': 'archive@example.com',
          'release_title': 'Archive This',
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

    await tester.tap(find.text('Archive Me'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(delegate.archivedPendingReleaseId, 30);
    expect(delegate.archivedReleaseTitle, 'Archive This');
  });

  testWidgets('Pending releases remove dialog can delete an item', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      pendingReleases: const [
        {
          'id': 31,
          'artist_name': 'Delete Me',
          'artist_email': 'delete@example.com',
          'release_title': 'Delete This',
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

    await tester.tap(find.text('Delete Me'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(delegate.deletedPendingReleaseId, 31);
    expect(delegate.deletedReleaseTitle, 'Delete This');
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

  testWidgets('Pending releases tab renders structured tables and reference image preview', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      pendingReleases: const [
        {
          'id': 22,
          'artist_name': 'Sea Echo',
          'artist_email': 'seaecho@example.com',
          'release_title': 'Blue Horizon',
          'status': 'pending',
          'created_at': '2026-03-18T10:00:00Z',
          'demo_submission_id': 77,
          'artist_data': <String, dynamic>{
            'artist_brand': 'Sea Echo Live',
            'website': 'https://seaecho.example.com',
          },
          'image_options': <Map<String, dynamic>>[
            {
              'id': 'img-1',
              'url': 'https://cdn.example.com/cover-option.png',
              'filename': 'cover-option.png',
            },
          ],
          'selected_image_id': 'img-1',
          'comments': <Map<String, dynamic>>[
            {
              'id': 1,
              'sender': 'label',
              'body': 'Artwork draft is ready for review.',
              'created_at': '2026-03-18T11:00:00Z',
            },
          ],
          'release_data': <String, dynamic>{
            'track_title': 'Blue Horizon',
            'catalog_number': 'ZR-101',
            'wav_download_url': 'https://files.example.com/blue-horizon.wav',
            'marketing_text': 'A warm melodic journey.',
          },
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

    await tester.tap(find.text('Sea Echo'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Artist details'), findsOneWidget);
    expect(find.text('Release details'), findsOneWidget);
    expect(find.text('Release images'), findsOneWidget);
    expect(find.text('Release forum'), findsOneWidget);
    expect(find.text('Artist brand'), findsOneWidget);
    expect(find.text('Catalog number'), findsOneWidget);
    expect(find.textContaining('cover-option.png'), findsOneWidget);
    expect(find.textContaining('Artist selected'), findsOneWidget);
    expect(find.text('Artwork draft is ready for review.'), findsOneWidget);
    expect(find.textContaining('"track_title"'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Pending releases tab shows empty image state when no artwork exists yet', (tester) async {
    final delegate = FakeAdminDashboardDelegate(
      pendingReleases: const [
        {
          'id': 23,
          'artist_name': 'No Artwork Yet',
          'artist_email': 'noart@example.com',
          'release_title': 'Unframed',
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

    await tester.tap(find.text('No Artwork Yet'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'No release images yet. Upload one or more options so the artist can choose the best fit.',
      ),
      findsOneWidget,
    );
  });
}
