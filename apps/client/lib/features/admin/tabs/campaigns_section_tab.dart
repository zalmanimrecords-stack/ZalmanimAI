import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import 'campaign_requests_tab.dart';
import 'campaigns_tab.dart';

/// Combined "CAMPAIGNS" section: one main tab split into two sub-tabs
/// (Campaigns and Campaign requests).
class CampaignsSectionTab extends StatefulWidget {
  const CampaignsSectionTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<CampaignsSectionTab> createState() => _CampaignsSectionTabState();
}

class _CampaignsSectionTabState extends State<CampaignsSectionTab> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: TabBar(
              tabs: [
                Tab(
                  icon: ZalmanimIcons.alienIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Campaigns',
                ),
                Tab(
                  icon: ZalmanimIcons.jellyfishIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Campaign requests',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                CampaignsTab(delegate: widget.delegate),
                CampaignRequestsTab(delegate: widget.delegate),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
