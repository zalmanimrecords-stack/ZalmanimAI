import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Tab showing tracks pending for release (artist submitted full details after approval).
class PendingReleasesTab extends StatefulWidget {
  const PendingReleasesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<PendingReleasesTab> createState() => _PendingReleasesTabState();
}

class _PendingReleasesTabState extends State<PendingReleasesTab> {
  final Set<int> _sendingReminderIds = <int>{};
  String _selectedStatusFilter = 'active';

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
        statusFilter: _selectedStatusFilter == 'active'
            ? null
            : _selectedStatusFilter,
      );
    } else if (action == _PendingReleaseRemovalAction.delete) {
      await widget.delegate.deletePendingRelease(
        pendingReleaseId,
        releaseTitle,
        statusFilter: _selectedStatusFilter == 'active'
            ? null
            : _selectedStatusFilter,
      );
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

    void maybeAdd(String label, String url,
        {String? fileName, bool allowAnyUrl = false}) {
      final normalized = url.trim();
      final canPreview =
          allowAnyUrl ? _looksLikeUrl(normalized) : _looksLikeImageUrl(normalized);
      if (normalized.isEmpty || seen.contains(normalized) || !canPreview) {
        return;
      }
      seen.add(normalized);
      previews.add(_ImagePreview(
        label: label,
        url: normalized,
        subtitle: (fileName ?? '').trim(),
      ));
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
                      final status = _formatValue(item['status']).isEmpty ? 'pending' : _formatValue(item['status']);
                      final demoSubmissionId = item['demo_submission_id'];
                      final fromDemo = demoSubmissionId != null;
                      final artistData = _asMap(item['artist_data']);
                      final releaseData = _asMap(item['release_data']);
                      final reminderBusy = item['id'] is int && _sendingReminderIds.contains(item['id']);
                      final imagePreviews = _imagePreviews(item);
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
                            artistName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (releaseTitle.isNotEmpty)
                                  _InfoPill(
                                    label: releaseTitle,
                                    background: scheme.primary.withValues(alpha: 0.10),
                                    foreground: scheme.primary,
                                  ),
                                _InfoPill(
                                  label: status.toUpperCase(),
                                  background: scheme.secondary.withValues(alpha: 0.12),
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
                            if (imagePreviews.isNotEmpty) ...[
                              _ImageGalleryCard(
                                title: 'Reference image',
                                previews: imagePreviews,
                                onOpenLink: _openExternalLink,
                              ),
                              const SizedBox(height: 12),
                            ],
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailsTableCard extends StatelessWidget {
  const _DetailsTableCard({
    required this.title,
    required this.rows,
    required this.onOpenLink,
  });

  final String title;
  final List<_DetailRow> rows;
  final Future<void> Function(String value) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FixedColumnWidth(156),
              1: FlexColumnWidth(),
            },
            children: [
              for (int i = 0; i < rows.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: i.isEven ? Colors.transparent : scheme.surfaceContainerHighest.withValues(alpha: 0.28),
                  ),
                  children: [
                    _DetailLabelCell(label: rows[i].label),
                    _DetailValueCell(
                      row: rows[i],
                      onOpenLink: onOpenLink,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailLabelCell extends StatelessWidget {
  const _DetailLabelCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _DetailValueCell extends StatelessWidget {
  const _DetailValueCell({
    required this.row,
    required this.onOpenLink,
  });

  final _DetailRow row;
  final Future<void> Function(String value) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            row.value,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          if (row.isLink) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onOpenLink(row.value),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open link'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageGalleryCard extends StatelessWidget {
  const _ImageGalleryCard({
    required this.title,
    required this.previews,
    required this.onOpenLink,
  });

  final String title;
  final List<_ImagePreview> previews;
  final Future<void> Function(String value) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.secondary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.secondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (int i = 0; i < previews.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _ImagePreviewTile(
                    preview: previews[i],
                    onOpenLink: onOpenLink,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewTile extends StatelessWidget {
  const _ImagePreviewTile({
    required this.preview,
    required this.onOpenLink,
  });

  final _ImagePreview preview;
  final Future<void> Function(String value) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (preview.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          preview.subtitle,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => onOpenLink(preview.url),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                preview.url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Text('Could not preview image'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLink = false,
  });

  final String label;
  final String value;
  final bool isLink;
}

class _ImagePreview {
  const _ImagePreview({
    required this.label,
    required this.url,
    this.subtitle = '',
  });

  final String label;
  final String url;
  final String subtitle;
}

enum _PendingReleaseRemovalAction {
  archive,
  delete,
}
