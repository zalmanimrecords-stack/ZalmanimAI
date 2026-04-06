import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import '../file_download.dart';

part 'pending_releases_tab_widgets.dart';

/// Tab showing tracks pending for release (artist submitted full details after approval).
class PendingReleasesTab extends StatefulWidget {
  const PendingReleasesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<PendingReleasesTab> createState() => _PendingReleasesTabState();
}

class _PendingReleasesTabState extends State<PendingReleasesTab> {
  final Set<int> _sendingReminderIds = <int>{};
  final Set<String> _busyImageOps = <String>{};
  String _selectedStatusFilter = 'active';

  String _imageBusyKey(int pendingReleaseId, String imageId, String op) =>
      '$pendingReleaseId|$imageId|$op';

  /// Busy key for [removePendingReleaseStoredImage] (URL-based delete).
  String _storedDeleteBusyKey(int pendingReleaseId, String imageUrl) =>
      '$pendingReleaseId|${imageUrl.hashCode}|sdel';

  /// Label/reference files on this API can be removed; external URLs cannot.
  bool _isServerStoredPendingReleaseImageUrl(String url) {
    final p = url.toLowerCase();
    return p.contains('/public/pending-release-label-image/') ||
        p.contains('/public/pending-release-reference-image/');
  }

  Future<void> _removePendingReleaseStoredImage(
      int pendingReleaseId, String imageUrl) async {
    final key = _storedDeleteBusyKey(pendingReleaseId, imageUrl);
    setState(() => _busyImageOps.add(key));
    try {
      await widget.delegate.apiClient.removePendingReleaseStoredImage(
        token: widget.delegate.token,
        pendingReleaseId: pendingReleaseId,
        imageUrl: imageUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image removed')),
      );
      await _reloadPendingReleases();
    } catch (e) {
      widget.delegate.showErrorSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busyImageOps.remove(key));
      }
    }
  }

  Future<void> _normalizePendingReleaseImage(
      int pendingReleaseId, String imageId) async {
    final key = _imageBusyKey(pendingReleaseId, imageId, 'jpg');
    setState(() => _busyImageOps.add(key));
    try {
      await widget.delegate.apiClient.normalizePendingReleaseImageToJpg3000(
        token: widget.delegate.token,
        pendingReleaseId: pendingReleaseId,
        imageId: imageId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Image converted to 3000×3000 JPG')),
      );
      await _reloadPendingReleases();
    } catch (e) {
      widget.delegate.showErrorSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busyImageOps.remove(key));
      }
    }
  }

  Future<void> _confirmDeleteStoredImage(
      int pendingReleaseId, String imageUrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove image'),
        content: const Text(
          'Remove this image? The file will be deleted on the server and artists will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _removePendingReleaseStoredImage(pendingReleaseId, imageUrl);
    }
  }

  Future<void> _sendReminder(Map<String, dynamic> item) async {
    final pendingReleaseId = item['id'];
    if (pendingReleaseId is! int) return;
    setState(() => _sendingReminderIds.add(pendingReleaseId));
    try {
      await widget.delegate.sendPendingReleaseReminder(
        pendingReleaseId,
        item['artist_name']?.toString() ?? 'artist',
      );
    } finally {
      if (mounted) {
        setState(() => _sendingReminderIds.remove(pendingReleaseId));
      }
    }
  }

  Future<void> _openExternalLink(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _applyStatusFilter(String value) async {
    setState(() => _selectedStatusFilter = value);
    await widget.delegate.loadPendingReleases(
      statusFilter: value == 'active' ? null : value,
    );
  }

  String? _statusFilterParam() =>
      _selectedStatusFilter == 'active' ? null : _selectedStatusFilter;

  Future<void> _reloadPendingReleases() => widget.delegate.loadPendingReleases(
        statusFilter: _statusFilterParam(),
      );

  String _mimeTypeForDownloadFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'application/octet-stream';
  }

  String _downloadFilenameForPreview(_ImagePreview preview, int index) {
    final s = preview.suggestedFilename;
    if (s != null && s.trim().isNotEmpty) return s.trim();
    final u = Uri.tryParse(preview.url);
    if (u != null && u.pathSegments.isNotEmpty) {
      final last = u.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    return 'image_${index + 1}.jpg';
  }

  Future<void> _downloadReleaseImage(String displayUrl, String filename) async {
    try {
      final bytes = await widget.delegate.apiClient.fetchUrlBytes(displayUrl);
      if (!mounted) return;
      triggerBrowserDownload(
        bytes,
        filename,
        mimeType: _mimeTypeForDownloadFilename(filename),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download started.')),
      );
    } catch (e) {
      if (!mounted) return;
      widget.delegate.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showRemovePendingReleaseDialog(
      Map<String, dynamic> item) async {
    final pendingReleaseId = item['id'];
    if (pendingReleaseId is! int) return;
    final releaseTitle = _formatValue(item['release_title']);
    final status = _formatValue(item['status']).toLowerCase();
    final action = await showDialog<_PendingReleaseRemovalAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove pending release'),
        content: Text(
          releaseTitle.isEmpty
              ? 'Choose whether to archive this pending release or delete it permanently.'
              : 'Choose whether to archive "$releaseTitle" or delete it permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: status == 'archived'
                ? null
                : () => Navigator.of(ctx).pop(_PendingReleaseRemovalAction.archive),
            child: const Text('Archive'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () =>
                Navigator.of(ctx).pop(_PendingReleaseRemovalAction.delete),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (action == _PendingReleaseRemovalAction.archive) {
      await widget.delegate.archivePendingRelease(
        pendingReleaseId,
        releaseTitle,
        statusFilter: _statusFilterParam(),
      );
    } else if (action == _PendingReleaseRemovalAction.delete) {
      await widget.delegate.deletePendingRelease(
        pendingReleaseId,
        releaseTitle,
        statusFilter: _statusFilterParam(),
      );
    }
  }

  Future<void> _uploadPendingReleaseImage(Map<String, dynamic> item) async {
    final pendingReleaseId = item['id'];
    if (pendingReleaseId is! int) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = (result == null || result.files.isEmpty) ? null : result.files.first;
    if (file == null || file.bytes == null || file.bytes!.isEmpty) return;
    try {
      await widget.delegate.apiClient.uploadPendingReleaseImage(
        token: widget.delegate.token,
        pendingReleaseId: pendingReleaseId,
        fileBytes: file.bytes!,
        filename: file.name.isEmpty ? 'release-image.png' : file.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded to pending release')),
      );
      await _reloadPendingReleases();
    } catch (e) {
      widget.delegate.showErrorSnackBar(e.toString());
    }
  }

  Future<void> _addPendingReleaseComment(Map<String, dynamic> item) async {
    final pendingReleaseId = item['id'];
    if (pendingReleaseId is! int) return;
    final controller = TextEditingController();
    try {
      final body = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add release update'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Update',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Post'),
            ),
          ],
        ),
      );
      if (body == null || body.trim().isEmpty) return;
      await widget.delegate.apiClient.addPendingReleaseComment(
        token: widget.delegate.token,
        pendingReleaseId: pendingReleaseId,
        body: body.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Release update posted')),
      );
      await _reloadPendingReleases();
    } catch (e) {
      widget.delegate.showErrorSnackBar(e.toString());
    } finally {
      controller.dispose();
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _formatValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is Iterable) {
      return value.map((entry) => entry?.toString() ?? '').where((entry) => entry.trim().isNotEmpty).join(', ');
    }
    return value.toString().trim();
  }

  String _prettyLabel(String key) {
    const explicitLabels = <String, String>{
      'artist_name': 'Artist name',
      'artist_email': 'Artist email',
      'artist_brand': 'Artist brand',
      'full_name': 'Full name',
      'release_title': 'Release title',
      'track_title': 'Track title',
      'catalog_number': 'Catalog number',
      'release_number': 'Release number',
      'release_date': 'Release date',
      'wav_download_url': 'WAV download link',
      'musical_style': 'Musical style',
      'genre': 'Genre',
      'mastering_required': 'Mastering required',
      'mastering_headroom_confirmed': '6 dB headroom confirmed',
      'cover_reference_image_url': 'Cover reference image',
      'cover_reference_image_name': 'Reference image file',
      'marketing_text': 'Marketing text',
      'release_story': 'Story / meaning',
      'demo_submission_id': 'Demo submission',
      'created_at': 'Submitted',
      'updated_at': 'Updated',
      'last_reminder_sent_at': 'Last reminder',
      'soundcloud': 'SoundCloud',
      'instagram': 'Instagram',
      'facebook': 'Facebook',
    };
    final explicit = explicitLabels[key];
    if (explicit != null) return explicit;
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  bool _looksLikeImageUrl(String value) {
    final lower = value.toLowerCase();
    return _looksLikeUrl(value) &&
        (lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp') ||
            lower.endsWith('.gif') ||
            lower.contains('/pending_release_references/') ||
            lower.contains('image'));
  }

  List<_DetailRow> _overviewRows(
    Map<String, dynamic> item, {
    required bool fromDemo,
  }) {
    final rows = <_DetailRow>[
      _DetailRow(label: 'Email', value: _formatValue(item['artist_email']), isLink: _looksLikeUrl(_formatValue(item['artist_email']))),
      _DetailRow(label: 'Submitted', value: _formatValue(item['created_at'])),
    ];
    final demoSubmissionId = _formatValue(item['demo_submission_id']);
    if (fromDemo && demoSubmissionId.isNotEmpty) {
      rows.add(_DetailRow(label: 'Demo submission', value: '#$demoSubmissionId'));
    }
    final lastReminderSentAt = _formatValue(item['last_reminder_sent_at']);
    if (lastReminderSentAt.isNotEmpty) {
      rows.add(_DetailRow(label: 'Last reminder', value: lastReminderSentAt));
    }
    return rows.where((row) => row.value.isNotEmpty).toList();
  }

  List<_DetailRow> _artistRows(Map<String, dynamic> artistData) {
    final rows = <_DetailRow>[];
    final orderedKeys = <String>[
      'artist_brand',
      'full_name',
      'website',
      'soundcloud',
      'instagram',
      'facebook',
    ];
    final consumed = <String>{};
    for (final key in orderedKeys) {
      final value = _formatValue(artistData[key]);
      if (value.isEmpty) continue;
      consumed.add(key);
      rows.add(_DetailRow(
        label: _prettyLabel(key),
        value: value,
        isLink: _looksLikeUrl(value),
      ));
    }
    for (final entry in artistData.entries) {
      if (consumed.contains(entry.key)) continue;
      final value = _formatValue(entry.value);
      if (value.isEmpty) continue;
      rows.add(_DetailRow(
        label: _prettyLabel(entry.key),
        value: value,
        isLink: _looksLikeUrl(value),
      ));
    }
    return rows;
  }

  List<_DetailRow> _releaseRows(Map<String, dynamic> releaseData) {
    final rows = <_DetailRow>[];
    final consumed = <String>{};

    void addValue(String label, dynamic rawValue, {String? consumeKey, bool isLink = false}) {
      final value = _formatValue(rawValue);
      if (value.isEmpty) return;
      if (consumeKey != null) consumed.add(consumeKey);
      rows.add(_DetailRow(label: label, value: value, isLink: isLink));
    }

    addValue('Track title', releaseData['track_title'], consumeKey: 'track_title');
    final catalogNumber = _formatValue(releaseData['catalog_number']);
    final releaseNumber = _formatValue(releaseData['release_number']);
    if (catalogNumber.isNotEmpty) {
      rows.add(_DetailRow(label: 'Catalog number', value: catalogNumber));
      consumed.addAll(<String>{'catalog_number', 'release_number'});
    } else if (releaseNumber.isNotEmpty) {
      rows.add(_DetailRow(label: 'Release number', value: releaseNumber));
      consumed.addAll(<String>{'catalog_number', 'release_number'});
    }
    addValue('Release date', releaseData['release_date'], consumeKey: 'release_date');
    final wavDownloadUrl = _formatValue(releaseData['wav_download_url']);
    if (wavDownloadUrl.isNotEmpty) {
      rows.add(_DetailRow(label: 'WAV download link', value: wavDownloadUrl, isLink: true));
      consumed.add('wav_download_url');
    }
    final musicalStyle = _formatValue(releaseData['musical_style']);
    final genre = _formatValue(releaseData['genre']);
    if (musicalStyle.isNotEmpty) {
      rows.add(_DetailRow(label: 'Musical style', value: musicalStyle));
      consumed.addAll(<String>{'musical_style', 'genre'});
    } else if (genre.isNotEmpty) {
      rows.add(_DetailRow(label: 'Genre', value: genre));
      consumed.addAll(<String>{'musical_style', 'genre'});
    }

    final masteringRequired = releaseData['mastering_required'];
    if (masteringRequired is bool) {
      rows.add(_DetailRow(
        label: 'Mastering',
        value: masteringRequired ? 'Required' : 'Not required',
      ));
      consumed.add('mastering_required');
    }

    final headroomConfirmed = releaseData['mastering_headroom_confirmed'];
    if (headroomConfirmed is bool) {
      rows.add(_DetailRow(
        label: '6 dB headroom confirmed',
        value: headroomConfirmed ? 'Yes' : 'No',
      ));
      consumed.add('mastering_headroom_confirmed');
    }

    addValue('Marketing text', releaseData['marketing_text'], consumeKey: 'marketing_text');
    addValue('Story / meaning', releaseData['release_story'], consumeKey: 'release_story');
    addValue('Notes', releaseData['notes'], consumeKey: 'notes');
    consumed.addAll(
        <String>{'cover_reference_image_name', 'cover_reference_image_url'});

    for (final entry in releaseData.entries) {
      if (consumed.contains(entry.key)) continue;
      final value = _formatValue(entry.value);
      if (value.isEmpty) continue;
      rows.add(_DetailRow(
        label: _prettyLabel(entry.key),
        value: value,
        isLink: _looksLikeUrl(value),
      ));
    }
    return rows;
  }

  List<_ImagePreview> _imagePreviews(Map<String, dynamic> item) {
    final releaseData = _asMap(item['release_data']);
    final previews = <_ImagePreview>[];
    final seen = <String>{};
    final selectedImageId = _formatValue(item['selected_image_id']);

    void maybeAdd(
      String label,
      String url, {
      String? fileName,
      bool allowAnyUrl = false,
      bool isSelected = false,
      String? managementImageId,
    }) {
      final normalized = url.trim();
      final canPreview =
          allowAnyUrl ? _looksLikeUrl(normalized) : _looksLikeImageUrl(normalized);
      if (normalized.isEmpty || seen.contains(normalized) || !canPreview) {
        return;
      }
      seen.add(normalized);
      var suggested = (fileName ?? '').trim();
      if (suggested.isEmpty) {
        final u = Uri.tryParse(normalized);
        if (u != null && u.pathSegments.isNotEmpty) {
          suggested = u.pathSegments.last;
        }
      }
      previews.add(_ImagePreview(
        label: label,
        url: normalized,
        subtitle: [
          (fileName ?? '').trim(),
          if (isSelected) 'Artist selected',
        ].where((part) => part.isNotEmpty).join(' - '),
        suggestedFilename: suggested.isEmpty ? null : suggested,
        managementImageId:
            (managementImageId ?? '').trim().isEmpty ? null : managementImageId!.trim(),
      ));
    }

    final rawImageOptions = item['image_options'];
    if (rawImageOptions is List) {
      for (final rawItem in rawImageOptions) {
        if (rawItem is! Map) continue;
        final imageId = _formatValue(rawItem['id']);
        maybeAdd(
          imageId == selectedImageId ? 'Selected image' : 'Image option',
          _formatValue(rawItem['url']),
          fileName: _formatValue(rawItem['filename']),
          allowAnyUrl: true,
          isSelected: imageId == selectedImageId,
          managementImageId: imageId.isNotEmpty ? imageId : null,
        );
      }
    }

    maybeAdd(
      'Cover reference',
      _formatValue(releaseData['cover_reference_image_url']),
      fileName: _formatValue(releaseData['cover_reference_image_name']),
      allowAnyUrl: true,
    );

    for (final entry in releaseData.entries) {
      final key = entry.key.toLowerCase();
      final value = _formatValue(entry.value);
      if (value.isEmpty) continue;
      if (key.contains('image') || key.contains('artwork') || key.contains('cover')) {
        maybeAdd(_prettyLabel(entry.key), value, allowAnyUrl: true);
      }
    }
    return previews;
  }

  /// Builds a plain-text summary of the release for copying.
  String _releaseDetailsText(Map<String, dynamic> item) {
    final buffer = StringBuffer();
    final overviewRows = _overviewRows(
      item,
      fromDemo: item['demo_submission_id'] != null,
    );
    final artistRows = _artistRows(_asMap(item['artist_data']));
    final releaseRows = _releaseRows(_asMap(item['release_data']));

    void writeSection(String title, List<_DetailRow> rows) {
      if (rows.isEmpty) return;
      buffer.writeln(title);
      for (final row in rows) {
        buffer.writeln('${row.label}: ${row.value}');
      }
      buffer.writeln();
    }

    writeSection('Overview', overviewRows);
    writeSection('Artist details', artistRows);
    writeSection('Release details', releaseRows);
    return buffer.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.delegate.pendingReleasesList;
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => widget.delegate.loadPendingReleases(
        statusFilter:
            _selectedStatusFilter == 'active' ? null : _selectedStatusFilter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Text(
                  'Pending for release',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedStatusFilter,
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'processed', child: Text('Processed')),
                    DropdownMenuItem(value: 'archived', child: Text('Archived')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _applyStatusFilter(value);
                  },
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => widget.delegate.loadPendingReleases(
                    statusFilter: _selectedStatusFilter == 'active'
                        ? null
                        : _selectedStatusFilter,
                  ),
                  icon: const Icon(ZalmanimIcons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No pending releases. When artists submit the form after their track is approved, they appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index] as Map<String, dynamic>;
                      final artistName = _formatValue(item['artist_name']).isEmpty ? '-' : _formatValue(item['artist_name']);
                      final artistEmail = _formatValue(item['artist_email']);
                      final releaseTitle = _formatValue(item['release_title']);
                      final artistData = _asMap(item['artist_data']);
                      final releaseData = _asMap(item['release_data']);
                      final trackTitle = _formatValue(releaseData['track_title']);
                      final displayTitle = trackTitle.isNotEmpty
                          ? trackTitle
                          : (releaseTitle.isNotEmpty
                              ? releaseTitle
                              : artistName);
                      final showArtistLine =
                          artistName != '-' && displayTitle != artistName;
                      final status = _formatValue(item['status']).isEmpty ? 'pending' : _formatValue(item['status']);
                      final demoSubmissionId = item['demo_submission_id'];
                      final fromDemo = demoSubmissionId != null;
                      final reminderBusy = item['id'] is int && _sendingReminderIds.contains(item['id']);
                      final imagePreviews = _imagePreviews(item);
                      final comments = item['comments'] is List
                          ? (item['comments'] as List)
                              .whereType<Map>()
                              .map((entry) => entry.map((key, value) =>
                                  MapEntry(key.toString(), value)))
                              .toList()
                          : const <Map<String, dynamic>>[];
                      final overviewRows = _overviewRows(item, fromDemo: fromDemo);
                      final artistRows = _artistRows(artistData);
                      final releaseRows = _releaseRows(releaseData);

                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          title: Text(
                            displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showArtistLine)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      artistName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (releaseTitle.isNotEmpty &&
                                        displayTitle != releaseTitle)
                                      _InfoPill(
                                        label: releaseTitle,
                                        background: scheme.primary.withOpacity(0.10),
                                        foreground: scheme.primary,
                                      ),
                                    _InfoPill(
                                      label: status.toUpperCase(),
                                      background: scheme.secondary.withOpacity(0.12),
                                      foreground: scheme.secondary,
                                    ),
                                    if (fromDemo)
                                      _InfoPill(
                                        label: 'Demo #$demoSubmissionId',
                                        background: scheme.surfaceContainerHighest,
                                        foreground: scheme.onSurfaceVariant,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: reminderBusy ? null : () => _sendReminder(item),
                                  icon: reminderBusy
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.mark_email_unread_outlined),
                                  label: Text(reminderBusy ? 'Sending...' : 'Send completion email'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: artistEmail.trim().isEmpty
                                      ? null
                                      : () => widget.delegate.showPendingReleaseMessageDialog(item),
                                  icon: const Icon(Icons.email_outlined),
                                  label: const Text('Message artist'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _showRemovePendingReleaseDialog(item),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remove'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _ImageGalleryCard(
                              title: 'Release images',
                              previews: imagePreviews,
                              onOpenLink: _openExternalLink,
                              resolveMediaUrl:
                                  widget.delegate.apiClient.resolveMediaUrl,
                              onDownloadReleaseImage:
                                  (preview, index, displayUrl) =>
                                      _downloadReleaseImage(
                                displayUrl,
                                _downloadFilenameForPreview(preview, index),
                              ),
                              pendingReleaseId: item['id'] as int,
                              busyImageOps: _busyImageOps,
                              imageBusyKey: _imageBusyKey,
                              storedDeleteBusyKey: _storedDeleteBusyKey,
                              isServerStoredImageUrl: _isServerStoredPendingReleaseImageUrl,
                              onDeleteStoredImage: _confirmDeleteStoredImage,
                              onNormalizeImage: _normalizePendingReleaseImage,
                              action: OutlinedButton.icon(
                                onPressed: () =>
                                    _uploadPendingReleaseImage(item),
                                icon: const Icon(Icons.upload_outlined),
                                label: const Text('Upload image'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _DetailsTableCard(title: 'Overview', rows: overviewRows, onOpenLink: _openExternalLink),
                            if (artistRows.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _DetailsTableCard(
                                title: 'Artist details',
                                rows: artistRows,
                                onOpenLink: _openExternalLink,
                              ),
                            ],
                            if (releaseRows.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _DetailsTableCard(
                                title: 'Release details',
                                rows: releaseRows,
                                onOpenLink: _openExternalLink,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _CommentFeedCard(
                              comments: comments,
                              onAddComment: () => _addPendingReleaseComment(item),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  tooltip: 'Copy all details',
                                  onPressed: () {
                                    final text = _releaseDetailsText(item);
                                    Clipboard.setData(ClipboardData(text: text));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Release details copied')),
                                    );
                                  },
                                ),
                                const Text('Copy all details', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
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
