import 'package:flutter/material.dart';

import '../../../core/models/campaign.dart';
import '../admin_dashboard_delegate.dart';

/// Campaigns tab: list, sort, create/edit/schedule/delete.
class CampaignsTab extends StatelessWidget {
  const CampaignsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  List<Campaign> _sortedCampaigns() {
    final list = delegate.campaignsList
        .map((e) => Campaign.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) {
      int cmp;
      switch (delegate.campaignsSortBy) {
        case 1:
          cmp = _compareString(a.scheduledAt ?? '', b.scheduledAt ?? '');
          break;
        case 2:
          cmp = _compareString(a.sentAt ?? '', b.sentAt ?? '');
          break;
        case 3:
          cmp = _compareString(a.status, b.status);
          break;
        default:
          cmp = _compareString(a.name, b.name);
      }
      return delegate.campaignsSortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = delegate.campaignsList;

    return RefreshIndicator(
      onRefresh: delegate.load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Unified Campaigns',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Send one content to social, Mailchimp, and WordPress. '
            'Create draft, then schedule or send now.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => delegate.showCreateCampaignDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Create campaign'),
              ),
              const SizedBox(width: 24),
              Text(
                'Sort by:',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: delegate.campaignsSortBy,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Name')),
                  DropdownMenuItem(value: 1, child: Text('Scheduled date')),
                  DropdownMenuItem(value: 2, child: Text('Sent date')),
                  DropdownMenuItem(value: 3, child: Text('Status')),
                ],
                onChanged: (v) =>
                    delegate.setCampaignsSort(v ?? 0, delegate.campaignsSortAsc),
              ),
              IconButton(
                icon: Icon(
                  delegate.campaignsSortAsc
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                ),
                tooltip: delegate.campaignsSortAsc ? 'Ascending' : 'Descending',
                onPressed: () => delegate.setCampaignsSort(
                  delegate.campaignsSortBy,
                  !delegate.campaignsSortAsc,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (campaigns.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No campaigns yet. Create one to get started.',
                ),
              ),
            )
          else
            ..._sortedCampaigns().map((c) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(c.name),
                  subtitle: Text(
                    'Status: ${c.status}'
                    '${c.scheduledAt != null ? ' · Scheduled: ${c.scheduledAt}' : ''}'
                    '${c.sentAt != null ? ' · Sent: ${c.sentAt}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.status == 'draft' || c.status == 'scheduled') ...[
                        if (c.status == 'draft')
                          TextButton(
                            onPressed: () =>
                                delegate.showScheduleCampaignDialog(c.id),
                            child: const Text('Schedule'),
                          ),
                        if (c.status == 'scheduled')
                          TextButton(
                            onPressed: () =>
                                delegate.cancelCampaignSchedule(c.id),
                            child: const Text('Cancel schedule'),
                          ),
                        if (c.status == 'draft' ||
                            c.status == 'scheduled')
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            tooltip: 'Edit',
                            onPressed: () => delegate.showEditCampaignDialog(
                              c.toJson(),
                            ),
                          ),
                        if (c.status == 'draft' || c.status == 'failed')
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Delete',
                            onPressed: () =>
                                delegate.deleteCampaign(c.id, c.name),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
