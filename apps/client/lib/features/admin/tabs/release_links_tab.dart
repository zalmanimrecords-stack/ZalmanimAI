import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/release.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

class ReleaseLinksTab extends StatefulWidget {
  const ReleaseLinksTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<ReleaseLinksTab> createState() => _ReleaseLinksTabState();
}

class _ReleaseLinksTabState extends State<ReleaseLinksTab> {
  final _releasesController = ScrollController();
  static const double _releaseItemHeight = 84;
  static const List<String> _minisiteThemes = [
    'nebula',
    'sunset_poster',
    'paperwave',
  ];

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

  /// Best URL to open the release minisite in a browser (public page when published, else preview).
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

  Future<void> _configureMinisite(Release release) async {
    var currentRelease = release;
    final minisite = Map<String, dynamic>.from(release.minisite);
    final theme = ValueNotifier<String>(release.minisiteTheme ?? _minisiteThemes.first);
    final isPublic = ValueNotifier<bool>(release.minisiteIsPublic);
    final descriptionController =
        TextEditingController(text: (minisite['description'] ?? '').toString());
    final downloadController =
        TextEditingController(text: (minisite['download_url'] ?? '').toString());
    final galleryController = TextEditingController(
      text: minisite['gallery_urls'] is List
          ? (minisite['gallery_urls'] as List)
              .map((item) => item?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .join('\n')
          : '',
    );
    final messageController = TextEditingController();

    Future<void> saveConfig(StateSetter setDialogState) async {
      final updated = await delegate.apiClient.updateReleaseMinisite(
        token: delegate.token,
        releaseId: currentRelease.id,
        theme: theme.value,
        isPublic: isPublic.value,
        description: descriptionController.text.trim(),
        downloadUrl: downloadController.text.trim(),
        galleryUrls: galleryController.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(),
      );
      setDialogState(() {
        currentRelease = Release.fromJson(updated);
      });
      await delegate.loadReleases();
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final previewUrl = currentRelease.minisitePreviewUrl == null
              ? ''
              : delegate.apiClient.resolveMediaUrl(currentRelease.minisitePreviewUrl);
          final publicUrl = currentRelease.minisitePublicUrl == null
              ? ''
              : delegate.apiClient.resolveMediaUrl(currentRelease.minisitePublicUrl);
          return AlertDialog(
            title: Text('Release minisite: ${currentRelease.title}'),
            content: SizedBox(
              width: 640,
              child: ListView(
                shrinkWrap: true,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: theme.value,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    items: _minisiteThemes
                        .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => theme.value = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isPublic.value,
                    title: const Text('Public link open to the world'),
                    onChanged: (value) => setDialogState(() => isPublic.value = value),
                  ),
                  if (publicUrl.isNotEmpty || previewUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Open minisite',
                      style: Theme.of(dialogContext).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    if (publicUrl.isNotEmpty)
                      _minisiteUrlRow(
                        dialogContext,
                        label: 'Public',
                        url: publicUrl,
                      ),
                    if (previewUrl.isNotEmpty)
                      _minisiteUrlRow(
                        dialogContext,
                        label: 'Preview',
                        url: previewUrl,
                      ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Release / artist description',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: downloadController,
                    decoration: const InputDecoration(labelText: 'Download URL'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: galleryController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Extra image URLs (one per line)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Optional message when sending to artist',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () async {
                          try {
                            await saveConfig(setDialogState);
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (e) {
                            if (mounted) delegate.showErrorSnackBar(e.toString());
                          }
                        },
                        child: const Text('Save minisite'),
                      ),
                      OutlinedButton(
                        onPressed: previewUrl.isEmpty ? null : () => _openUrl(previewUrl),
                        child: const Text('Preview'),
                      ),
                      OutlinedButton(
                        onPressed: publicUrl.isEmpty ? null : () => _openUrl(publicUrl),
                        child: const Text('Open public'),
                      ),
                      FilledButton.tonal(
                        onPressed: () async {
                          try {
                            await saveConfig(setDialogState);
                            await delegate.apiClient.sendReleaseMinisite(
                              token: delegate.token,
                              releaseId: currentRelease.id,
                              message: messageController.text.trim(),
                            );
                            await delegate.loadReleases();
                            if (!mounted || !dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Minisite link sent to artist')),
                            );
                          } catch (e) {
                            if (mounted) delegate.showErrorSnackBar(e.toString());
                          }
                        },
                        child: const Text('Send to artist'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
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

  Widget _minisiteUrlRow(
    BuildContext context, {
    required String label,
    required String url,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                SelectableText(url),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openUrl(url),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _sortedAdminReleases() {
    final list = List<Map<String, dynamic>>.from(
      delegate.adminReleasesList.map((e) => e as Map<String, dynamic>),
    );
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

  @override
  Widget build(BuildContext context) {
    final sortedReleases = _sortedAdminReleases();
    final bulkScanCount = sortedReleases
        .map(Release.fromJson)
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

    return RefreshIndicator(
      onRefresh: delegate.loadReleases,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Text(
                'Release links & minisites',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: bulkScanCount == 0
                    ? null
                    : () => _scanAllMissingReleaseLinks(sortedReleases),
                icon: const Icon(ZalmanimIcons.sync, size: 18),
                label: Text('Scan all missing links ($bulkScanCount)'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Scan and review streaming/store links, then configure each release’s public minisite (theme, copy, publish). '
            'Releases waiting for link review are listed first.',
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
                  final rawRelease = sortedReleases[index];
                  final release = Release.fromJson(rawRelease);
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
                              FilledButton.icon(
                                icon: const Icon(Icons.palette_outlined, size: 18),
                                label: const Text('Minisite'),
                                onPressed: () => _configureMinisite(release),
                              ),
                              Builder(
                                builder: (_) {
                                  final minisiteUrl = _minisiteExternalUrl(release);
                                  return IconButton(
                                    tooltip: minisiteUrl == null
                                        ? 'Configure minisite first'
                                        : 'Open minisite in browser',
                                    icon: const Icon(Icons.open_in_new, size: 20),
                                    onPressed: minisiteUrl == null
                                        ? null
                                        : () => _openUrl(minisiteUrl),
                                  );
                                },
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
        ],
      ),
    );
  }
}
