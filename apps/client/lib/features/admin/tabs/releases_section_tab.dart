import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import 'pending_releases_tab.dart';
import 'releases_tab.dart';

/// Parent tab "Releases" with two sub-tabs: Releases and Pending for release.
class ReleasesSectionTab extends StatelessWidget {
  const ReleasesSectionTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: 1,
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: TabBar(
              tabs: [
                Tab(
                  icon: ZalmanimIcons.squidIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Releases',
                ),
                Tab(
                  icon: ZalmanimIcons.squidIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Pending for release',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ReleasesTab(delegate: delegate),
                PendingReleasesTab(delegate: delegate),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
