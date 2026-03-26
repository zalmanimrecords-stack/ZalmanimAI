import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import 'pending_releases_tab.dart';
import 'release_links_tab.dart';
import 'releases_tab.dart';

/// Parent tab "Releases" with sub-tabs for catalog, links, minisites, and pending releases.
class ReleasesSectionTab extends StatelessWidget {
  const ReleasesSectionTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
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
                  text: 'Catalog',
                ),
                Tab(
                  icon: ZalmanimIcons.squidIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Link discovery',
                ),
                Tab(
                  icon: ZalmanimIcons.squidIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Minisites',
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
                ReleaseLinksTab(delegate: delegate),
                ReleaseLinksTab(delegate: delegate, focusMinisites: true),
                PendingReleasesTab(delegate: delegate),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
