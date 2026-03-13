import 'package:flutter/material.dart';

import '../../../core/models/campaign.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Campaigns tab: list, sort, create/edit/schedule/delete.
class CampaignsTab extends StatefulWidget {
  const CampaignsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<CampaignsTab> createState() => _CampaignsTabState();
}

class _CampaignsTabState extends State<CampaignsTab> {
  final _scrollController = ScrollController();

  AdminDashboardDelegate get delegate => widget.delegate;

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      delegate.loadMoreCampaigns();
    }
  }

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
    final campaigns = _sortedCampaigns();

    return RefreshIndicator(
      onRefresh: delegate.loadCampaigns,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: campaigns.isEmpty ? 4 : campaigns.length + 4,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Text(
              'Unified Campaigns',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            );
          }
          if (index == 1) {
            return const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'Send one content to social, Mailchimp, and WordPress. '
                'Create draft, then schedule or send now.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            );
          }
          if (index == 2) {
            return Row(
              children: [
                FilledButton.icon(
                  onPressed: () => delegate.showCreateCampaignDialog(),
                  icon: const Icon(ZalmanimIcons.add),
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
                    delegate.campaignsSortAsc ? ZalmanimIcons.arrowUp : ZalmanimIcons.arrowDown,
                    size: 18,
                  ),
                  tooltip: delegate.campaignsSortAsc ? 'Ascending' : 'Descending',
                  onPressed: () => delegate.setCampaignsSort(
                    delegate.campaignsSortBy,
                    !delegate.campaignsSortAsc,
                  ),
                ),
              ],
            );
          }
          if (index == 3 && campaigns.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No campaigns yet. Create one to get started.'),
              ),
            );
          }
          if (index == campaigns.length + 3) {
            if (delegate.campaignsLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (delegate.campaignsHasMore) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Scroll down to load more campaigns',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return const SizedBox(height: 8);
          }

          final c = campaigns[index - 3];
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
                        onPressed: () => delegate.showScheduleCampaignDialog(c.id),
                        child: const Text('Schedule'),
                      ),
                    if (c.status == 'scheduled')
                      TextButton(
                        onPressed: () => delegate.cancelCampaignSchedule(c.id),
                        child: const Text('Cancel schedule'),
                      ),
                    if (c.status == 'draft' || c.status == 'scheduled')
                      IconButton(
                        icon: const Icon(ZalmanimIcons.edit, color: Colors.orange),
                        tooltip: 'Edit',
                        onPressed: () => delegate.showEditCampaignDialog(c.toJson()),
                      ),
                    if (c.status == 'draft' || c.status == 'failed')
                      IconButton(
                        icon: const Icon(ZalmanimIcons.delete, color: Colors.red),
                        tooltip: 'Delete',
                        onPressed: () => delegate.deleteCampaign(c.id, c.name),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}