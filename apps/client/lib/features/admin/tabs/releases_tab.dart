import 'package:flutter/material.dart';

import '../../../core/models/artist.dart';
import '../../../core/models/catalog_track.dart';
import '../../../core/models/release.dart';
import '../admin_dashboard_delegate.dart';

/// Releases tab: catalog (import, sync, DataTable) + releases list with set artists.
class ReleasesTab extends StatelessWidget {
  const ReleasesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

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
      int cmp = col == 2 ? _compareDate(av, bv) : _compareString(av, bv);
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

  List<Map<String, dynamic>> _sortedAdminReleases() {
    final list = List<Map<String, dynamic>>.from(
      delegate.adminReleasesList.map((e) => e as Map<String, dynamic>),
    );
    list.sort((a, b) {
      final aIds = a['artist_ids'] as List<dynamic>? ?? [];
      final bIds = b['artist_ids'] as List<dynamic>? ?? [];
      final aNo = aIds.isEmpty;
      final bNo = bIds.isEmpty;
      if (aNo != bNo) return aNo ? -1 : 1;
      final cmp = delegate.releasesSortBy == 1
          ? _compareDate(
              (a['created_at'] as String?) ?? '',
              (b['created_at'] as String?) ?? '',
            )
          : _compareString(
              (a['title'] as String?) ?? '',
              (b['title'] as String?) ?? '',
            );
      return delegate.releasesSortAsc ? cmp : -cmp;
    });
    return list;
  }

  String _artistNameForId(int id) {
    for (final a in delegate.artistsListForReleases) {
      if (a is Map<String, dynamic> && a['id'] == id) {
        final artist = Artist.fromJson(a);
        return artist.displayName;
      }
    }
    return 'Artist $id';
  }

  @override
  Widget build(BuildContext context) {
    final catalogTracks = delegate.catalogTracksList;
    final filteredCount = _filteredCatalogTracks().length;
    final sortedCatalog = _sortedCatalogTracks();
    final sortedReleases = _sortedAdminReleases();
    final searchQuery = delegate.releasesSearchController.text.trim();

    return RefreshIndicator(
      onRefresh: delegate.load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Catalog (Releases)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Catalog metadata from Proton export. Import CSV, then Sync to '
            'artists to create releases. Schema: Catalog Number, Release '
            'Title, Pre-Order/Release Date, UPC, ISRC, Artists, Track Title, '
            'Mix, Duration.',
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
                icon: const Icon(Icons.upload_file),
                label: const Text('Import CSV'),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty
                    ? null
                    : delegate.syncReleasesFromCatalog,
                icon: const Icon(Icons.sync),
                label: const Text('Sync to artists'),
                style: FilledButton.styleFrom(
                  backgroundColor: catalogTracks.isEmpty
                      ? null
                      : Theme.of(context).colorScheme.tertiary,
                ),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty
                    ? null
                    : delegate.syncOriginalArtistsFromArtists,
                icon: const Icon(Icons.sync_alt),
                label: const Text('Original Artist ← Brand'),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty
                    ? null
                    : delegate.createMissingOriginalArtists,
                icon: const Icon(Icons.person_add),
                label: const Text('Create missing artists'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (catalogTracks.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: delegate.releasesSearchController,
                    decoration: InputDecoration(
                      hintText:
                          'Search releases by catalog #, title, artist, '
                          'ISRC, UPC, mix…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                if (searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '$filteredCount of ${catalogTracks.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (catalogTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No catalog tracks. Use Import CSV to load a Proton '
                  'catalog export.',
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  sortColumnIndex: delegate.catalogSortColumnIndex,
                  sortAscending: delegate.catalogSortAsc,
                  columns: [
                    _dataColumn('Catalog #', 0),
                    _dataColumn('Release', 1),
                    _dataColumn('Release Date', 2),
                    _dataColumn('UPC', 3),
                    _dataColumn('ISRC', 4),
                    _dataColumn('Original Artists', 5),
                    _dataColumn('Track', 6),
                    _dataColumn('Mix', 7),
                    _dataColumn('Duration', 8),
                  ],
                  rows: sortedCatalog
                      .map(
                        (t) => DataRow(
                          cells: [
                            DataCell(SelectableText(t.catalogNumber)),
                            DataCell(SelectableText(t.releaseTitle)),
                            DataCell(SelectableText(t.releaseDateDisplay)),
                            DataCell(SelectableText(t.upc ?? '')),
                            DataCell(SelectableText(t.isrc ?? '')),
                            DataCell(SelectableText(t.originalArtists ?? '')),
                            DataCell(SelectableText(t.trackTitle ?? '')),
                            DataCell(SelectableText(t.mixTitle ?? '')),
                            DataCell(SelectableText(t.duration ?? '')),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text(
                'Releases (from API)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
                onChanged: (v) =>
                    delegate.setReleasesSort(v ?? 0, delegate.releasesSortAsc),
              ),
              IconButton(
                icon: Icon(
                  delegate.releasesSortAsc
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
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
            'Releases without an artist are highlighted in orange. Use '
            '"Associate with artist" to link a release to an artist.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (delegate.adminReleasesList.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No releases yet. Import catalog above and use Sync to '
                'artists to create releases.',
              ),
            )
          else
            ...sortedReleases.map<Widget>((r) {
              final release = Release.fromJson(r);
              final artistNames = release.artistIds
                  .map((id) => _artistNameForId(id))
                  .join(', ');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: release.hasNoArtist
                    ? Colors.orange.withValues(alpha: 0.12)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: release.hasNoArtist
                      ? const BorderSide(color: Colors.orange, width: 2)
                      : BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: ListTile(
                  title: SelectableText(release.title),
                  subtitle: SelectableText(
                    release.hasNoArtist
                        ? 'No artist assigned'
                        : artistNames,
                  ),
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Associate with artist'),
                    onPressed: () => delegate.showSetArtistsDialog(r),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  DataColumn _dataColumn(String label, int columnIndex) {
    return DataColumn(
      label: Text(label),
      onSort: (int index, bool ascending) {
        delegate.setCatalogSort(index, ascending);
      },
    );
  }
}
