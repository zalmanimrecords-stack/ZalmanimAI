import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/catalog_track.dart';
import '../../../core/models/release.dart';
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
  final _releasesController = ScrollController();
  final _catalogHorizontalController = ScrollController();

  static const double _catalogRowHeight = 44;
  static const double _catalogHeaderHeight = 44;
  static const double _catalogMinWidth = 1300;
  static const double _releaseItemHeight = 84;

  AdminDashboardDelegate get delegate => widget.delegate;

  static const Map<String, String> _platformLabels = {
    'spotify': 'Spotify',
    'apple_music': 'Apple Music',
    'youtube': 'YouTube',
    'soundcloud': 'SoundCloud',
    'beatport': 'Beatport',
    'bandcamp': 'Bandcamp',
    'deezer': 'Deezer',
    'tidal': 'TIDAL',
    'amazon_music': 'Amazon Music',
  };

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  String _platformLabel(String key) => _platformLabels[key] ?? key;

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      delegate.showErrorSnackBar('Invalid URL: $value');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      delegate.showErrorSnackBar('Could not open URL: $value');
    }
  }

  Future<void> _scanReleaseLinks(Map<String, dynamic> release) async {
    try {
      final result = await delegate.apiClient.queueReleaseLinkScan(
        token: delegate.token,
        releaseIds: [(release['id'] as num).toInt()],
      );
      await delegate.loadReleases();
      if (!mounted) return;
      final message = (result['message'] ?? 'Release link scan queued.').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      delegate.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _scanAllMissingReleaseLinks(List<Map<String, dynamic>> releases) async {
    final releaseIds = releases
        .map(Release.fromJson)
        .where(
          (release) =>
              release.platformLinks.isEmpty &&
              release.pendingLinkCandidatesCount == 0,
        )
        .map((release) => release.id)
        .toList();
    if (releaseIds.isEmpty) {
      delegate.showErrorSnackBar('No releases need link scanning right now.');
      return;
    }
    try {
      final result = await delegate.apiClient.queueReleaseLinkScan(
        token: delegate.token,
        releaseIds: releaseIds,
      );
      await delegate.loadReleases();
      if (!mounted) return;
      final message = (result['message'] ?? 'Release link scan queued.').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      delegate.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _reviewReleaseLinks(Release release) async {
    List<Map<String, dynamic>> candidates = [];
    var loadingCandidates = true;

    try {
      final rows = await delegate.apiClient.fetchReleaseLinkCandidates(
        token: delegate.token,
        releaseId: release.id,
      );
      candidates = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      if (mounted) delegate.showErrorSnackBar(e.toString());
    } finally {
      loadingCandidates = false;
    }

    Future<void> reloadCandidates(StateSetter setDialogState) async {
      setDialogState(() => loadingCandidates = true);
      try {
        final rows = await delegate.apiClient.fetchReleaseLinkCandidates(
          token: delegate.token,
          releaseId: release.id,
        );
        final mapped = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        setDialogState(() {
          candidates = mapped;
          loadingCandidates = false;
        });
      } catch (e) {
        setDialogState(() => loadingCandidates = false);
        if (mounted) delegate.showErrorSnackBar(e.toString());
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> approveCandidate(Map<String, dynamic> candidate) async {
            try {
              await delegate.apiClient.approveReleaseLinkCandidate(
                token: delegate.token,
                releaseId: release.id,
                candidateId: (candidate['id'] as num).toInt(),
              );
              await reloadCandidates(setDialogState);
              await delegate.loadReleases();
            } catch (e) {
              if (mounted) delegate.showErrorSnackBar(e.toString());
            }
          }

          Future<void> rejectCandidate(Map<String, dynamic> candidate) async {
            try {
              await delegate.apiClient.rejectReleaseLinkCandidate(
                token: delegate.token,
                releaseId: release.id,
                candidateId: (candidate['id'] as num).toInt(),
              );
              await reloadCandidates(setDialogState);
              await delegate.loadReleases();
            } catch (e) {
              if (mounted) delegate.showErrorSnackBar(e.toString());
            }
          }

          return AlertDialog(
            title: Text('Review release links: ${release.title}'),
            content: SizedBox(
              width: 760,
              child: loadingCandidates
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ))
                  : candidates.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No link candidates found yet for this release.'),
                          ),
                        )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        final candidate = candidates[index];
                        final status = (candidate['status'] ?? '').toString();
                        final confidence = (candidate['confidence'] as num?)?.toDouble() ??
                            double.tryParse(candidate['confidence']?.toString() ?? '') ??
                            0;
                        final url = (candidate['url'] ?? '').toString();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(label: Text(_platformLabel((candidate['platform'] ?? '').toString()))),
                                Chip(label: Text('Status: $status')),
                                Chip(label: Text('Confidence: ${confidence.toStringAsFixed(2)}')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(url),
                            const SizedBox(height: 6),
                            Text(
                              'Matched title: ${(candidate['match_title'] ?? '-').toString()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Matched artist: ${(candidate['match_artist'] ?? '-').toString()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: url.isEmpty ? null : () => _openUrl(url),
                                  child: const Text('Open'),
                                ),
                                FilledButton(
                                  onPressed: status == 'approved' ? null : () => approveCandidate(candidate),
                                  child: const Text('Approve'),
                                ),
                                OutlinedButton(
                                  onPressed: status == 'rejected' ? null : () => rejectCandidate(candidate),
                                  child: const Text('Reject'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => reloadCandidates(setDialogState),
                child: const Text('Refresh'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _catalogController.addListener(_handleScroll);
    _releasesController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _catalogController.removeListener(_handleScroll);
    _releasesController.removeListener(_handleScroll);
    _catalogController.dispose();
    _releasesController.dispose();
    _catalogHorizontalController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    for (final controller in [_catalogController, _releasesController]) {
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

  @override
  Widget build(BuildContext context) {
    final catalogTracks = delegate.catalogTracksList;
    final sortedCatalog = _sortedCatalogTracks();
    final sortedReleases = _sortedAdminReleases();
    final bulkScanCount = sortedReleases
        .map(Release.fromJson)
        .where(
          (release) =>
              release.platformLinks.isEmpty &&
              release.pendingLinkCandidatesCount == 0,
        )
        .length;
    final searchQuery = delegate.releasesSearchController.text.trim();
    final catalogListHeight = math.min<double>(
      math.max<double>(sortedCatalog.length * _catalogRowHeight, 220),
      520,
    );
    final releasesListHeight = math.min<double>(
      math.max<double>(sortedReleases.length * _releaseItemHeight, 220),
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
                'Releases (from API)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: bulkScanCount == 0
                    ? null
                    : () => _scanAllMissingReleaseLinks(sortedReleases),
                icon: const Icon(ZalmanimIcons.sync, size: 18),
                label: Text('Scan all missing links ($bulkScanCount)'),
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
            'Releases without an artist are highlighted in orange. Click a release to view every link candidate that was found.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (sortedReleases.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('No releases loaded yet.'),
            )
          else
            SizedBox(
              height: releasesListHeight,
              child: ListView.builder(
                controller: _releasesController,
                itemCount: sortedReleases.length,
                itemBuilder: (context, index) {
                  final release = Release.fromJson(sortedReleases[index]);
                  final artistNames = release.artistNames.join(', ');
                  final approvedLinks = release.platformLinks.entries.toList()
                    ..sort((a, b) => _platformLabel(a.key).compareTo(_platformLabel(b.key)));
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: release.hasNoArtist ? Colors.orange.withValues(alpha: 0.12) : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: release.hasNoArtist
                          ? const BorderSide(color: Colors.orange, width: 2)
                          : BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    child: ListTile(
                      onTap: () => _reviewReleaseLinks(release),
                      title: Text(
                        release.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            release.hasNoArtist ? 'No artist assigned' : artistNames,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          if (approvedLinks.isEmpty)
                            const Text(
                              'No approved release links yet.',
                              style: TextStyle(fontSize: 12),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: approvedLinks
                                  .map(
                                    (entry) => ActionChip(
                                      label: Text(_platformLabel(entry.key)),
                                      onPressed: () => _openUrl(entry.value),
                                    ),
                                  )
                                  .toList(),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(ZalmanimIcons.sync, size: 18),
                                label: const Text('Scan links'),
                                onPressed: () => _scanReleaseLinks(sortedReleases[index]),
                              ),
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.rule_folder_outlined, size: 18),
                                label: Text(
                                  release.pendingLinkCandidatesCount > 0
                                      ? 'Review (${release.pendingLinkCandidatesCount})'
                                      : 'Review links',
                                ),
                                onPressed: () => _reviewReleaseLinks(release),
                              ),
                              if (release.lastLinkScanAt != null &&
                                  release.lastLinkScanAt!.trim().isNotEmpty)
                                Chip(
                                  label: Text(
                                    'Last scan: ${release.lastLinkScanAt!.replaceFirst("T", " ").split(".").first}',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(ZalmanimIcons.personAdd, size: 18),
                            label: const Text('Associate with artist'),
                            onPressed: () => delegate.showSetArtistsDialog(sortedReleases[index]),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
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
