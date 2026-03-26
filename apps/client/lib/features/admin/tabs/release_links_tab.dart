import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/release.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

class ReleaseLinksTab extends StatefulWidget {
  const ReleaseLinksTab({
    super.key,
    required this.delegate,
    this.embedded = false,
    this.showTitle = true,
  });

  final AdminDashboardDelegate delegate;
  final bool embedded;
  final bool showTitle;

  @override
  State<ReleaseLinksTab> createState() => _ReleaseLinksTabState();
}

class _ReleaseLinksTabState extends State<ReleaseLinksTab> {
  final _releasesController = ScrollController();
  /// Rough height per row for the releases list viewport (cards include minisite URLs).
  static const double _releaseItemHeight = 168;
  bool _showOnlyReadyMinisites = false;

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

  String _platformLabel(String key) => _platformLabels[key] ?? key;

  bool _hasReadyMinisite(Release release) => _minisiteExternalUrl(release) != null;

  /// Best URL to open the release minisite in a browser (public when published, else preview).
  String? _minisiteExternalUrl(Release release) {
    final publicRaw = release.minisitePublicUrl?.trim() ?? '';
    final previewRaw = release.minisitePreviewUrl?.trim() ?? '';
    if (release.minisiteIsPublic && publicRaw.isNotEmpty) {
      return delegate.apiClient.resolveMediaUrl(publicRaw);
    }
    if (previewRaw.isNotEmpty) {
      return delegate.apiClient.resolveMediaUrl(previewRaw);
    }
    if (publicRaw.isNotEmpty) {
      return delegate.apiClient.resolveMediaUrl(publicRaw);
    }
    return null;
  }

  String? _resolveMinisiteMediaUrl(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return null;
    return delegate.apiClient.resolveMediaUrl(t);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  Widget _minisiteUrlRow(
    BuildContext context, {
    required String label,
    required String url,
    required bool isVisitorLink,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                url,
                style: TextStyle(
                  fontSize: 13,
                  color: isVisitorLink ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () => _copyToClipboard(url),
            ),
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () => _openUrl(url),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMinisiteLinksSection(BuildContext context, Release release) {
    final theme = Theme.of(context);
    final publicResolved = _resolveMinisiteMediaUrl(release.minisitePublicUrl);
    final previewResolved = _resolveMinisiteMediaUrl(release.minisitePreviewUrl);
    final sameUrl = publicResolved != null &&
        previewResolved != null &&
        publicResolved == previewResolved;

    if (publicResolved == null && previewResolved == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Minisite: no URLs yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final children = <Widget>[
      const SizedBox(height: 8),
      Text(
        'Minisite',
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
    ];

    if (sameUrl) {
      final url = publicResolved;
      final label = release.minisiteIsPublic
          ? 'Public page — visitors use this link'
          : 'Preview — not published yet (visitors do not have a public page)';
      children.add(
        _minisiteUrlRow(
          context,
          label: label,
          url: url,
          isVisitorLink: release.minisiteIsPublic,
        ),
      );
    } else {
      if (publicResolved != null) {
        final label = release.minisiteIsPublic
            ? 'Public page — visitors use this link'
            : 'Public URL — not published (visitors cannot open this yet)';
        children.add(
          _minisiteUrlRow(
            context,
            label: label,
            url: publicResolved,
            isVisitorLink: release.minisiteIsPublic,
          ),
        );
      }
      if (previewResolved != null && !sameUrl) {
        if (publicResolved != null) {
          children.add(const SizedBox(height: 10));
        }
        children.add(
          _minisiteUrlRow(
            context,
            label: 'Preview page — draft / staff view',
            url: previewResolved,
            isVisitorLink: false,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  @override
  void initState() {
    super.initState();
    _releasesController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _releasesController.removeListener(_handleScroll);
    _releasesController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_releasesController.hasClients) return;
    final position = _releasesController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      delegate.loadMoreReleasesPage();
    }
  }

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

  Future<void> _refreshReleaseArtwork(Release release) async {
    try {
      final updated = await delegate.apiClient.refreshReleaseCoverArt(
        token: delegate.token,
        releaseId: release.id,
      );
      await delegate.loadReleases();
      if (!mounted) return;
      final refreshed = Release.fromJson(updated);
      final hasArtwork = (refreshed.coverImageUrl?.trim().isNotEmpty ?? false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasArtwork
                ? 'Artwork updated for ${release.title}'
                : 'No artwork found yet for ${release.title}',
          ),
        ),
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
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
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
                            final artworkUrl = delegate.apiClient.resolveMediaUrl(
                              (candidate['raw_payload'] as Map?)?['artwork_url']?.toString(),
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (artworkUrl.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        artworkUrl,
                                        height: 120,
                                        width: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Chip(
                                      label: Text(
                                        _platformLabel((candidate['platform'] ?? '').toString()),
                                      ),
                                    ),
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
                                      onPressed: status == 'approved'
                                          ? null
                                          : () => approveCandidate(candidate),
                                      child: const Text('Approve'),
                                    ),
                                    OutlinedButton(
                                      onPressed: status == 'rejected'
                                          ? null
                                          : () => rejectCandidate(candidate),
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

  List<Map<String, dynamic>> _sortedAdminReleases() {
    final list = List<Map<String, dynamic>>.from(
      delegate.adminReleasesList.map((e) => e as Map<String, dynamic>),
    );
    if (_showOnlyReadyMinisites) {
      list.retainWhere((item) => _hasReadyMinisite(Release.fromJson(item)));
    }
    list.sort((a, b) {
      final releaseA = Release.fromJson(a);
      final releaseB = Release.fromJson(b);
      final aNeedsReview = releaseA.pendingLinkCandidatesCount > 0;
      final bNeedsReview = releaseB.pendingLinkCandidatesCount > 0;
      if (aNeedsReview != bNeedsReview) return aNeedsReview ? -1 : 1;
      final aMissingApproved = releaseA.platformLinks.isEmpty;
      final bMissingApproved = releaseB.platformLinks.isEmpty;
      if (aMissingApproved != bMissingApproved) return aMissingApproved ? -1 : 1;
      return releaseA.title.toLowerCase().compareTo(releaseB.title.toLowerCase());
    });
    return list;
  }

  List<Widget> _buildContent(BuildContext context) {
    final sortedReleases = _sortedAdminReleases();
    final allReleases = delegate.adminReleasesList
        .map((e) => Release.fromJson(e as Map<String, dynamic>))
        .toList();
    final readyMinisiteCount = allReleases.where(_hasReadyMinisite).length;
    final bulkScanCount = allReleases
        .where(
          (release) =>
              release.platformLinks.isEmpty &&
              release.pendingLinkCandidatesCount == 0,
        )
        .length;
    final releasesListHeight = math.min<double>(
      math.max<double>(sortedReleases.length * _releaseItemHeight, 220),
      640,
    );

    return [
      if (widget.showTitle)
        Row(
          children: [
            const Text(
              'Release link discovery',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: bulkScanCount == 0
                  ? null
                  : () => _scanAllMissingReleaseLinks(
                        allReleases.map((release) => release.toJson()).toList(),
                      ),
              icon: const Icon(ZalmanimIcons.sync, size: 18),
              label: Text('Scan all missing links ($bulkScanCount)'),
            ),
          ],
        )
      else
        Row(
          children: [
            const Expanded(
              child: Text(
                'Releases, link discovery, minisites',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: bulkScanCount == 0
                  ? null
                  : () => _scanAllMissingReleaseLinks(
                        allReleases.map((release) => release.toJson()).toList(),
                      ),
              icon: const Icon(ZalmanimIcons.sync, size: 18),
              label: Text('Scan all missing links ($bulkScanCount)'),
            ),
          ],
        ),
      const SizedBox(height: 8),
      Text(
        'Scan and review streaming/store link candidates, keep minisites ready, and backfill release artwork from the best sources we can find.',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: Text('Ready minisite ($readyMinisiteCount)'),
            selected: _showOnlyReadyMinisites,
            onSelected: (value) => setState(() => _showOnlyReadyMinisites = value),
          ),
          if (_showOnlyReadyMinisites)
            Text(
              '${sortedReleases.length} releases shown',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (sortedReleases.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('No releases loaded yet for this filter.'),
        )
      else
        SizedBox(
          height: releasesListHeight,
          child: ListView.builder(
            controller: _releasesController,
            itemCount: sortedReleases.length,
            itemBuilder: (context, index) {
              final rawRelease = sortedReleases[index];
              final release = Release.fromJson(rawRelease);
              final minisiteUrl = _minisiteExternalUrl(release);
              final artistNames = release.artistNames.join(', ');
              final coverImageUrl = delegate.apiClient.resolveMediaUrl(release.coverImageUrl);
              final approvedLinks = release.platformLinks.entries.toList()
                ..sort((a, b) => _platformLabel(a.key).compareTo(_platformLabel(b.key)));
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: coverImageUrl.isEmpty
                      ? const CircleAvatar(child: Icon(Icons.album_outlined))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            coverImageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const CircleAvatar(child: Icon(Icons.album_outlined)),
                          ),
                        ),
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
                        artistNames.isEmpty ? 'No artist assigned' : artistNames,
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
                      _buildMinisiteLinksSection(context, release),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(ZalmanimIcons.sync, size: 18),
                            label: const Text('Scan links'),
                            onPressed: () => _scanReleaseLinks(rawRelease),
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
                          OutlinedButton.icon(
                            icon: const Icon(Icons.image_search_outlined, size: 18),
                            label: Text(
                              (release.coverImageUrl?.trim().isNotEmpty ?? false)
                                  ? 'Refresh artwork'
                                  : 'Find artwork',
                            ),
                            onPressed: () => _refreshReleaseArtwork(release),
                          ),
                          Tooltip(
                            message: minisiteUrl == null
                                ? 'No minisite URL for this release yet'
                                : 'Open minisite in browser',
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('View minisite'),
                              onPressed: minisiteUrl == null
                                  ? null
                                  : () => _openUrl(minisiteUrl),
                            ),
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
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Open'),
                    onPressed: () => _reviewReleaseLinks(release),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      );
    }
    return RefreshIndicator(
      onRefresh: delegate.loadReleases,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: content,
      ),
    );
  }
}
