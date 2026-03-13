import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Tab showing tracks pending for release (artist submitted full details after approval).
class PendingReleasesTab extends StatelessWidget {
  const PendingReleasesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final items = delegate.pendingReleasesList;
    return RefreshIndicator(
      onRefresh: () => delegate.loadPendingReleases(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Text(
                  'Pending for release',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: null,
                  hint: const Text('All statuses'),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'processed', child: Text('Processed')),
                  ],
                  onChanged: (v) => delegate.loadPendingReleases(statusFilter: v),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => delegate.loadPendingReleases(),
                  icon: const Icon(ZalmanimIcons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No pending releases. When artists submit the form after their track is approved, they appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index] as Map<String, dynamic>;
                      final artistName = item['artist_name']?.toString() ?? '-';
                      final artistEmail = item['artist_email']?.toString() ?? '';
                      final releaseTitle = item['release_title']?.toString() ?? '';
                      final status = item['status']?.toString() ?? 'pending';
                      final createdAt = item['created_at']?.toString() ?? '';
                      final artistData = item['artist_data'] is Map ? item['artist_data'] as Map<String, dynamic> : <String, dynamic>{};
                      final releaseData = item['release_data'] is Map ? item['release_data'] as Map<String, dynamic> : <String, dynamic>{};
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          title: Text(artistName),
                          subtitle: Text('$releaseTitle · $status'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Email: $artistEmail', style: const TextStyle(fontSize: 13)),
                                  Text('Submitted: $createdAt', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  if (artistData.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text('Artist details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    SelectableText(
                                      const JsonEncoder.withIndent('  ').convert(artistData),
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                  ],
                                  if (releaseData.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text('Release details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    SelectableText(
                                      const JsonEncoder.withIndent('  ').convert(releaseData),
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
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
