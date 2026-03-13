import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Reports tab: links to report actions (artists no tracks, etc.).
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: delegate.load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Reports',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Export and view reports (artists, releases, campaigns). '
            'More report types can be added here.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.personOff),
              title: const Text('Artist reminders'),
              subtitle: const Text(
                'Artists with no catalog release in the last X months. '
                'Run report, send reminder emails.',
              ),
              onTap: () =>
                  delegate.showArtistRemindersReport(context),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.reports),
              title: const Text('Artists'),
              subtitle: const Text(
                'Artist list and data for DB import (e.g. CSV).',
              ),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Reports: export options coming soon.',
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.releases),
              title: const Text('Releases'),
              subtitle: const Text('Releases and catalog summary.'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Reports: export options coming soon.',
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.campaigns),
              title: const Text('Campaigns'),
              subtitle: const Text('Campaign history and delivery status.'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Reports: export options coming soon.',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
