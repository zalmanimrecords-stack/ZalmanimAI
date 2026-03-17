import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String? _portalBaseUrl;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPortalUrl();
  }

  Future<void> _loadPortalUrl() async {
    try {
      final data = await widget.delegate.apiClient.fetchSystemSettings(widget.delegate.token);
      final url = (data['artist_portal_base_url'] ?? '').toString().trim();
      if (mounted) {
        setState(() {
          _portalBaseUrl = url.isEmpty ? 'https://artists.zalmanim.com' : url.replaceFirst(RegExp(r'/+$'), '');
          _settingsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _portalBaseUrl = 'https://artists.zalmanim.com';
          _settingsLoaded = true;
        });
      }
    }
  }

  String _formLink() {
    final base = _portalBaseUrl ?? 'https://artists.zalmanim.com';
    return '$base/#/pending-release';
  }

  /// Builds a plain-text summary of the release for copying.
  String _releaseDetailsText(Map<String, dynamic> item) {
    final artistName = item['artist_name']?.toString() ?? '-';
    final artistEmail = item['artist_email']?.toString() ?? '';
    final releaseTitle = item['release_title']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'pending';
    final createdAt = item['created_at']?.toString() ?? '';
    final artistData = item['artist_data'] is Map ? item['artist_data'] as Map<String, dynamic> : <String, dynamic>{};
    final releaseData = item['release_data'] is Map ? item['release_data'] as Map<String, dynamic> : <String, dynamic>{};
    final buffer = StringBuffer();
    buffer.writeln('Artist: $artistName');
    buffer.writeln('Email: $artistEmail');
    buffer.writeln('Release title: $releaseTitle');
    buffer.writeln('Status: $status');
    buffer.writeln('Submitted: $createdAt');
    if (artistData.isNotEmpty) {
      buffer.writeln('Artist details:');
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(artistData));
    }
    if (releaseData.isNotEmpty) {
      buffer.writeln('Release details:');
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(releaseData));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.delegate.pendingReleasesList;
    return RefreshIndicator(
      onRefresh: () => widget.delegate.loadPendingReleases(),
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
                  value: null,
                  hint: const Text('All statuses'),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'processed', child: Text('Processed')),
                  ],
                  onChanged: (v) => widget.delegate.loadPendingReleases(statusFilter: v),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => widget.delegate.loadPendingReleases(),
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
                      final artistName = item['artist_name']?.toString() ?? '-';
                      final artistEmail = item['artist_email']?.toString() ?? '';
                      final releaseTitle = item['release_title']?.toString() ?? '';
                      final status = item['status']?.toString() ?? 'pending';
                      final createdAt = item['created_at']?.toString() ?? '';
                      final demoSubmissionId = item['demo_submission_id'];
                      final fromDemo = demoSubmissionId != null;
                      final artistData = item['artist_data'] is Map ? item['artist_data'] as Map<String, dynamic> : <String, dynamic>{};
                      final releaseData = item['release_data'] is Map ? item['release_data'] as Map<String, dynamic> : <String, dynamic>{};
                      final formLink = _settingsLoaded ? _formLink() : null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          title: Text(artistName),
                          subtitle: Text(fromDemo
                              ? '$releaseTitle · $status · From demo #$demoSubmissionId'
                              : '$releaseTitle · $status'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (formLink != null) ...[
                                    const Text(
                                      'Release details form',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      formLink,
                                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', decoration: TextDecoration.underline),
                                    ),
                                    Row(
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: formLink));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Form link copied')),
                                            );
                                          },
                                          icon: const Icon(Icons.copy, size: 18),
                                          label: const Text('Copy link'),
                                        ),
                                      ],
                                    ),
                                    const Text(
                                      'Artist receives the form link with a one-time token by email when their track is approved.',
                                      style: TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  const Text('Release details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('Artist: $artistName', style: const TextStyle(fontSize: 13)),
                                  SelectableText('Email: $artistEmail', style: const TextStyle(fontSize: 13)),
                                  Text('Release title: $releaseTitle', style: const TextStyle(fontSize: 13)),
                                  Text('Status: $status', style: const TextStyle(fontSize: 13)),
                                  Text('Submitted: $createdAt', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                  if (artistData.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text('Artist details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    SelectableText(
                                      const JsonEncoder.withIndent('  ').convert(artistData),
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                  ],
                                  if (releaseData.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text('Release / track data', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    SelectableText(
                                      const JsonEncoder.withIndent('  ').convert(releaseData),
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
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
