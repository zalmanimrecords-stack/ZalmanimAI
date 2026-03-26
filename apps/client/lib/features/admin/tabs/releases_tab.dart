import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import 'release_links_tab.dart';

/// Releases tab: catalog actions + one unified release management list.
class ReleasesTab extends StatefulWidget {
  const ReleasesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<ReleasesTab> createState() => _ReleasesTabState();
}

class _ReleasesTabState extends State<ReleasesTab> {
  AdminDashboardDelegate get delegate => widget.delegate;

  @override
  Widget build(BuildContext context) {
    final catalogTracks = delegate.catalogTracksList;
    final searchQuery = delegate.releasesSearchController.text.trim();

    return RefreshIndicator(
      onRefresh: delegate.loadReleases,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Releases',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Import and sync catalog data here, then manage every release from one unified list.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: delegate.importCatalogCsv,
                icon: const Icon(ZalmanimIcons.upload),
                label: const Text('Import CSV'),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty ? null : delegate.syncReleasesFromCatalog,
                icon: const Icon(ZalmanimIcons.sync),
                label: const Text('Sync to artists'),
                style: FilledButton.styleFrom(
                  backgroundColor: catalogTracks.isEmpty
                      ? null
                      : Theme.of(context).colorScheme.tertiary,
                ),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty ? null : delegate.syncOriginalArtistsFromArtists,
                icon: const Icon(ZalmanimIcons.sync),
                label: const Text('Original Artist <- Brand'),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty ? null : delegate.createMissingOriginalArtists,
                icon: const Icon(ZalmanimIcons.personAdd),
                label: const Text('Create missing artists'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: delegate.releasesSearchController,
            decoration: const InputDecoration(
              hintText: 'Search one release list by title, artist, status, UPC, ISRC, platform...',
              prefixIcon: Icon(ZalmanimIcons.search),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Catalog rows loaded: ${catalogTracks.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (searchQuery.isNotEmpty)
                Text(
                  'Filtering unified release list by: "$searchQuery"',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Click any release to open everything related to its minisite and link discovery in one place.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ReleaseLinksTab(
            delegate: delegate,
            embedded: true,
            showTitle: false,
          ),
        ],
      ),
    );
  }
}
