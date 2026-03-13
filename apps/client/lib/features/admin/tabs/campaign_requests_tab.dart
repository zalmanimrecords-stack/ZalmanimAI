import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Tab showing artist campaign requests (artists asking the label for a release campaign).
class CampaignRequestsTab extends StatelessWidget {
  const CampaignRequestsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final requests = delegate.campaignRequestsList;
    return RefreshIndicator(
      onRefresh: () => delegate.loadCampaignRequests(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Text(
                  'Campaign requests',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: null,
                  hint: const Text('All statuses'),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (v) => delegate.loadCampaignRequests(statusFilter: v),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => delegate.loadCampaignRequests(),
                  icon: const Icon(ZalmanimIcons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          Expanded(
            child: requests.isEmpty
                ? const Center(
                    child: Text(
                      'No campaign requests. Artists can request campaigns from their portal.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final r = requests[index] as Map<String, dynamic>;
                      final id = r['id'] as int?;
                      final artistName = r['artist_name']?.toString() ?? '-';
                      final releaseTitle = r['release_title']?.toString() ?? 'No release';
                      final message = r['message']?.toString().trim() ?? '';
                      final status = r['status']?.toString() ?? 'pending';
                      final createdAt = r['created_at']?.toString() ?? '';
                      final isPending = status == 'pending';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(artistName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Release: $releaseTitle'),
                              if (message.isNotEmpty) Text('Message: $message'),
                              Text(
                                'Status: $status · $createdAt',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          trailing: isPending && id != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () => delegate.updateCampaignRequestStatus(id, 'approved'),
                                      child: const Text('Approve'),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton(
                                      onPressed: () => delegate.updateCampaignRequestStatus(id, 'rejected'),
                                      child: const Text('Reject'),
                                    ),
                                  ],
                                )
                              : Chip(
                                  label: Text(status),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
