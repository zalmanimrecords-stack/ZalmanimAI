import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/catalog_track.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Releases tab: catalog (import, sync, list) + releases list with set artists.
class ReleasesTab extends StatefulWidget {
  const ReleasesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<ReleasesTab> createState() => _ReleasesTabState();
}

class _ReleasesTabState extends State<ReleasesTab> {
  final _catalogController = ScrollController();
  final _catalogHorizontalController = ScrollController();

  static const double _catalogRowHeight = 44;
  static const double _catalogHeaderHeight = 44;
  static const double _catalogMinWidth = 1300;
  AdminDashboardDelegate get delegate => widget.delegate;

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  void initState() {
    super.initState();
    _catalogController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _catalogController.removeListener(_handleScroll);
    _catalogController.dispose();
    _catalogHorizontalController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    for (final controller in [_catalogController]) {
      if (!controller.hasClients) continue;
      final position = controller.position;
      if (position.pixels >= position.maxScrollExtent - 240) {
        delegate.loadMoreReleasesPage();
        return;
      }
    }
  }

  List<CatalogTrack> _filteredCatalogTracks() {
    final q = delegate.releasesSearchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      return delegate.catalogTracksList
          .map((e) => CatalogTrack.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return delegate.catalogTracksList
        .map((e) => CatalogTrack.fromJson(e as Map<String, dynamic>))
        .where((t) {
          return t.catalogNumber.toLowerCase().contains(q) ||
              t.releaseTitle.toLowerCase().contains(q) ||
              (t.trackTitle ?? '').toLowerCase().contains(q) ||
              (t.originalArtists ?? '').toLowerCase().contains(q) ||
              (t.isrc ?? '').toLowerCase().contains(q) ||
              (t.upc ?? '').toLowerCase().contains(q) ||
              (t.mixTitle ?? '').toLowerCase().contains(q);
        })
        .toList();
  }

  List<CatalogTrack> _sortedCatalogTracks() {
    final list = _filteredCatalogTracks();
    final col = delegate.catalogSortColumnIndex;
    if (col == null) return list;
    list.sort((a, b) {
      final av = _cellValue(a, col);
      final bv = _cellValue(b, col);
      final cmp = col == 2 ? _compareDate(av, bv) : _compareString(av, bv);
      return delegate.catalogSortAsc ? cmp : -cmp;
    });
    return list;
  }

  String _cellValue(CatalogTrack t, int col) {
    switch (col) {
      case 0:
        return t.catalogNumber;
      case 1:
        return t.releaseTitle;
      case 2:
        return t.releaseDateDisplay;
      case 3:
        return t.upc ?? '';
      case 4:
        return t.isrc ?? '';
      case 5:
        return t.originalArtists ?? '';
      case 6:
        return t.trackTitle ?? '';
      case 7:
        return t.mixTitle ?? '';
      case 8:
        return t.duration ?? '';
      default:
        return '';
    }
  }

  int _compareDate(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    try {
      return DateTime.parse(a).compareTo(DateTime.parse(b));
    } catch (_) {
      return a.compareTo(b);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogTracks = delegate.catalogTracksList;
    final sortedCatalog = _sortedCatalogTracks();
    final searchQuery = delegate.releasesSearchController.text.trim();
    final catalogListHeight = math.min<double>(
      math.max<double>(sortedCatalog.length * _catalogRowHeight, 220),
      520,
    );

    return RefreshIndicator(
      onRefresh: delegate.loadReleases,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Catalog (Releases)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Catalog metadata from Proton export. Import CSV, then Sync to artists to create releases.',
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
          if (catalogTracks.isNotEmpty) ...[
            TextField(
              controller: delegate.releasesSearchController,
              decoration: const InputDecoration(
                hintText: 'Search releases by catalog #, title, artist, ISRC, UPC, mix...',
                prefixIcon: Icon(ZalmanimIcons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            if (searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${sortedCatalog.length} loaded matches',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (catalogTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No catalog tracks. Use Import CSV to load a Proton catalog export.'),
              ),
            )
          else
            _buildCatalogList(context, sortedCatalog, catalogListHeight),
          if (delegate.releasesPageLoadingMore || delegate.releasesPageHasMore)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: delegate.releasesPageLoadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        'Scroll to the bottom of the lists to load more',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text(
                'Catalog (from API)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              Text(
                'Sort (after unassigned):',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: delegate.releasesSortBy,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Title')),
                  DropdownMenuItem(value: 1, child: Text('Date')),
                ],
                onChanged: (v) => delegate.setReleasesSort(v ?? 0, delegate.releasesSortAsc),
              ),
              IconButton(
                icon: Icon(
                  delegate.releasesSortAsc ? ZalmanimIcons.arrowUp : ZalmanimIcons.arrowDown,
                  size: 18,
                ),
                tooltip: delegate.releasesSortAsc ? 'Ascending' : 'Descending',
                onPressed: () => delegate.setReleasesSort(
                  delegate.releasesSortBy,
                  !delegate.releasesSortAsc,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Use the Link discovery tab to scan and review streaming and store links for each release.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogList(BuildContext context, List<CatalogTrack> tracks, double height) {
    const columns = <double>[140, 220, 130, 140, 140, 220, 220, 180, 110];
    const labels = <String>[
      'Catalog #',
      'Release',
      'Release Date',
      'UPC',
      'ISRC',
      'Original Artists',
      'Track',
      'Mix',
      'Duration',
    ];
    final width = math.max<double>(
      columns.reduce((value, element) => value + element).toDouble(),
      _catalogMinWidth,
    );

    return Scrollbar(
      controller: _catalogHorizontalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _catalogHorizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Container(
                height: _catalogHeaderHeight,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: List.generate(labels.length, (index) {
                    return InkWell(
                      onTap: () => delegate.setCatalogSort(index, delegate.catalogSortColumnIndex == index ? !delegate.catalogSortAsc : true),
                      child: SizedBox(
                        width: columns[index],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  labels[index],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (delegate.catalogSortColumnIndex == index)
                                Icon(
                                  delegate.catalogSortAsc ? ZalmanimIcons.arrowDropUp : ZalmanimIcons.arrowDropDown,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(
                height: height,
                child: ListView.builder(
                  controller: _catalogController,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final t = tracks[index];
                    final values = <String>[
                      t.catalogNumber,
                      t.releaseTitle,
                      t.releaseDateDisplay,
                      t.upc ?? '',
                      t.isrc ?? '',
                      t.originalArtists ?? '',
                      t.trackTitle ?? '',
                      t.mixTitle ?? '',
                      t.duration ?? '',
                    ];
                    return SizedBox(
                      height: _catalogRowHeight,
                      child: Row(
                        children: List.generate(values.length, (cellIndex) {
                          return SizedBox(
                            width: columns[cellIndex],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  values[cellIndex].isEmpty ? '-' : values[cellIndex],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
