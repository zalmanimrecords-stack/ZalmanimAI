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
  static const double _releaseItemHeight = 168;
  static const List<String> _themes = ['nebula', 'sunset_poster', 'paperwave'];
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

  String? _resolveMinisiteMediaUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return delegate.apiClient.resolveMediaUrl(value);
  }

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

  bool _hasReadyMinisite(Release release) => _minisiteExternalUrl(release) != null;

  bool _matchesSearch(Release release, String query) {
    if (query.isEmpty) return true;
    final haystacks = <String>[
      release.title,
      release.status,
      release.artistNames.join(' '),
      release.minisiteSlug ?? '',
      release.minisiteTheme ?? '',
      release.minisitePreviewUrl ?? '',
      release.minisitePublicUrl ?? '',
      release.coverImageSourceUrl ?? '',
      release.platformLinks.keys.join(' '),
      release.platformLinks.values.join(' '),
    ];
    return haystacks.any((value) => value.toLowerCase().contains(query));
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  Widget _urlRow(BuildContext context, String label, String url, {bool highlight = false}) {
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
                  color: highlight ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _copyToClipboard(url),
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy, size: 20),
            ),
            IconButton(
              onPressed: () => _openUrl(url),
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMinisiteLinksSection(BuildContext context, Release release) {
    final publicUrl = _resolveMinisiteMediaUrl(release.minisitePublicUrl);
    final previewUrl = _resolveMinisiteMediaUrl(release.minisitePreviewUrl);
    if (publicUrl == null && previewUrl == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Minisite: no URLs yet.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Minisite',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (publicUrl != null)
          _urlRow(
            context,
            release.minisiteIsPublic ? 'Public page' : 'Public URL (not published)',
            publicUrl,
            highlight: release.minisiteIsPublic,
          ),
        if (previewUrl != null) _urlRow(context, 'Preview page', previewUrl),
      ],
    );
  }

  Future<void> _scanReleaseLinks(Map<String, dynamic> release) async {
    try {
      final result = await delegate.apiClient.queueReleaseLinkScan(
        token: delegate.token,
        releaseIds: [(release['id'] as num).toInt()],
      );
      await delegate.loadReleases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result['message'] ?? 'Release link scan queued.').toString())),
      );
    } catch (e) {
      if (mounted) delegate.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _scanAllMissingReleaseLinks(List<Map<String, dynamic>> releases) async {
    final releaseIds = releases
        .map(Release.fromJson)
        .where((release) => release.platformLinks.isEmpty && release.pendingLinkCandidatesCount == 0)
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result['message'] ?? 'Release link scan queued.').toString())),
      );
    } catch (e) {
      if (mounted) delegate.showErrorSnackBar(e.toString());
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (refreshed.coverImageUrl?.trim().isNotEmpty ?? false)
                ? 'Artwork updated for ${release.title}'
                : 'No artwork found yet for ${release.title}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) delegate.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _openReleaseWorkbench(Release release) async {
    Release currentRelease = release;
    List<Map<String, dynamic>> candidates = [];
    bool loadingCandidates = true;
    bool minisiteBusy = false;
    String selectedTheme =
        (release.minisiteTheme ?? release.minisite['theme']?.toString() ?? 'nebula').trim();
    if (!_themes.contains(selectedTheme)) selectedTheme = _themes.first;
    bool minisiteIsPublic = release.minisiteIsPublic;
    final descriptionController =
        TextEditingController(text: (release.minisite['description'] ?? '').toString());
    final downloadController =
        TextEditingController(text: (release.minisite['download_url'] ?? '').toString());
    final galleryController = TextEditingController(
      text: ((release.minisite['gallery_urls'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .join('\n'),
    );
    final sendMessageController = TextEditingController();

    Future<void> reloadRelease(StateSetter setDialogState) async {
      await delegate.loadReleases();
      if (!mounted) return;
      final raw = delegate.adminReleasesList
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .firstWhere(
            (row) => (row['id'] as num?)?.toInt() == currentRelease.id,
            orElse: () => currentRelease.toJson(),
          );
      currentRelease = Release.fromJson(raw);
      setDialogState(() {
        minisiteIsPublic = currentRelease.minisiteIsPublic;
      });
    }

    Future<void> reloadCandidates(StateSetter setDialogState) async {
      setDialogState(() => loadingCandidates = true);
      try {
        final rows = await delegate.apiClient.fetchReleaseLinkCandidates(
          token: delegate.token,
          releaseId: currentRelease.id,
        );
        candidates = rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      } catch (e) {
        if (mounted) delegate.showErrorSnackBar(e.toString());
      } finally {
        setDialogState(() => loadingCandidates = false);
      }
    }

    try {
      final rows = await delegate.apiClient.fetchReleaseLinkCandidates(
        token: delegate.token,
        releaseId: release.id,
      );
      candidates = rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      if (mounted) delegate.showErrorSnackBar(e.toString());
    } finally {
      loadingCandidates = false;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final artistNames = currentRelease.artistNames.join(', ');
          final coverImageUrl = delegate.apiClient.resolveMediaUrl(currentRelease.coverImageUrl);
          final publicUrl = _resolveMinisiteMediaUrl(currentRelease.minisitePublicUrl);
          final previewUrl = _resolveMinisiteMediaUrl(currentRelease.minisitePreviewUrl);
          final approvedLinks = currentRelease.platformLinks.entries.toList()
            ..sort((a, b) => _platformLabel(a.key).compareTo(_platformLabel(b.key)));

          Future<void> approveCandidate(Map<String, dynamic> candidate) async {
            try {
              await delegate.apiClient.approveReleaseLinkCandidate(
                token: delegate.token,
                releaseId: currentRelease.id,
                candidateId: (candidate['id'] as num).toInt(),
              );
              await reloadCandidates(setDialogState);
              await reloadRelease(setDialogState);
            } catch (e) {
              if (mounted) delegate.showErrorSnackBar(e.toString());
            }
          }

          Future<void> rejectCandidate(Map<String, dynamic> candidate) async {
            try {
              await delegate.apiClient.rejectReleaseLinkCandidate(
                token: delegate.token,
                releaseId: currentRelease.id,
                candidateId: (candidate['id'] as num).toInt(),
              );
              await reloadCandidates(setDialogState);
              await reloadRelease(setDialogState);
            } catch (e) {
              if (mounted) delegate.showErrorSnackBar(e.toString());
            }
          }

          Future<void> saveMinisite() async {
            setDialogState(() => minisiteBusy = true);
            try {
              final updated = await delegate.apiClient.updateReleaseMinisite(
                token: delegate.token,
                releaseId: currentRelease.id,
                theme: selectedTheme,
                isPublic: minisiteIsPublic,
                description: descriptionController.text.trim(),
                downloadUrl: downloadController.text.trim(),
                galleryUrls: galleryController.text
                    .split('\n')
                    .map((line) => line.trim())
                    .where((line) => line.isNotEmpty)
                    .toList(),
              );
              currentRelease = Release.fromJson(updated);
              await reloadRelease(setDialogState);
            } catch (e) {
              if (mounted) delegate.showErrorSnackBar(e.toString());
            } finally {
              setDialogState(() => minisiteBusy = false);
            }
          }

          Future<void> sendMinisite() async {
            setDialogState(() => minisiteBusy = true);
            try {
              final updated = await delegate.apiClient.sendReleaseMinisite(
                token: delegate.token,
                releaseId: currentRelease.id,
                message: sendMessageController.text.trim(),
              );
              currentRelease = Release.fromJson(updated);
              await reloadRelease(setDialogState);
            } catch (e) {
              if (mounted) delegate.showErrorSnackBar(e.toString());
            } finally {
              setDialogState(() => minisiteBusy = false);
            }
          }

          return AlertDialog(
            title: Text(currentRelease.title),
            content: SizedBox(
              width: 920,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artistNames.isEmpty ? 'No artist assigned' : artistNames,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('Status: ${currentRelease.status}')),
                        Chip(label: Text('Pending review: ${currentRelease.pendingLinkCandidatesCount}')),
                        if (_hasReadyMinisite(currentRelease)) const Chip(label: Text('Minisite ready')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (coverImageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          coverImageUrl,
                          width: 132,
                          height: 132,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('Minisite', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedTheme,
                      decoration: const InputDecoration(
                        labelText: 'Theme',
                        border: OutlineInputBorder(),
                      ),
                      items: _themes
                          .map((theme) => DropdownMenuItem(value: theme, child: Text(theme)))
                          .toList(),
                      onChanged: minisiteBusy
                          ? null
                          : (value) => setDialogState(() => selectedTheme = value ?? selectedTheme),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Publish minisite publicly'),
                      value: minisiteIsPublic,
                      onChanged: minisiteBusy
                          ? null
                          : (value) => setDialogState(() => minisiteIsPublic = value),
                    ),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: downloadController,
                      decoration: const InputDecoration(
                        labelText: 'Download URL',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: galleryController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Gallery image URLs (one per line)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _buildMinisiteLinksSection(context, currentRelease),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sendMessageController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Message to artist',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: minisiteBusy ? null : saveMinisite,
                          child: Text(minisiteBusy ? 'Saving...' : 'Save minisite'),
                        ),
                        OutlinedButton(
                          onPressed: minisiteBusy ? null : sendMinisite,
                          child: const Text('Send to artist'),
                        ),
                        if (publicUrl != null)
                          OutlinedButton(
                            onPressed: () => _openUrl(publicUrl),
                            child: const Text('Open public'),
                          ),
                        if (previewUrl != null)
                          OutlinedButton(
                            onPressed: () => _openUrl(previewUrl),
                            child: const Text('Preview'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Link discovery', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _scanReleaseLinks(currentRelease.toJson()),
                          icon: const Icon(ZalmanimIcons.sync, size: 18),
                          label: const Text('Scan links'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _refreshReleaseArtwork(currentRelease),
                          icon: const Icon(Icons.image_search_outlined, size: 18),
                          label: const Text('Find artwork'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (approvedLinks.isNotEmpty)
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
                    if (loadingCandidates)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (candidates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No link candidates found yet for this release.'),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
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
                              const SizedBox(height: 6),
                              SelectableText(url),
                              const SizedBox(height: 6),
                              Text('Matched title: ${(candidate['match_title'] ?? '-').toString()}'),
                              Text('Matched artist: ${(candidate['match_artist'] ?? '-').toString()}'),
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await reloadCandidates(setDialogState);
                  await reloadRelease(setDialogState);
                },
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
    final query = delegate.releasesSearchController.text.trim().toLowerCase();
    final list = List<Map<String, dynamic>>.from(
      delegate.adminReleasesList.map((e) => e as Map<String, dynamic>),
    );
    list.retainWhere((item) {
      final release = Release.fromJson(item);
      if (_showOnlyReadyMinisites && !_hasReadyMinisite(release)) return false;
      return _matchesSearch(release, query);
    });
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
        .where((release) => release.platformLinks.isEmpty && release.pendingLinkCandidatesCount == 0)
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
              'Release management',
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
        ),
      const SizedBox(height: 8),
      Text(
        'One unified release list. Click a release to manage minisite, artwork, and link discovery together.',
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
              final release = Release.fromJson(sortedReleases[index]);
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
                  onTap: () => _openReleaseWorkbench(release),
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
                    ],
                  ),
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Open'),
                    onPressed: () => _openReleaseWorkbench(release),
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
