import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import '../file_download.dart';

class DemosTab extends StatelessWidget {
  const DemosTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  static Future<void> _confirmDeleteDemo(
    BuildContext context,
    AdminDashboardDelegate delegate,
    Map<String, dynamic> item,
  ) async {
    final id = item['id'] as int?;
    final artistName = (item['artist_name'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete demo submission?'),
        content: Text(
          'Are you sure you want to delete demo #$id${artistName.isNotEmpty ? ' ($artistName)' : ''}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await delegate.deleteDemoSubmission(item);
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'in_review':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  /// Formats submission date (ISO string or null) for display.
  static String? _formatSubmittedAt(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    try {
      final dt = DateTime.parse(s);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s;
    }
  }

  /// Track name from submission fields (e.g. artist portal submission).
  static String? _getTrackName(Map<String, dynamic> item) {
    final fields = item['fields'];
    if (fields is! Map<String, dynamic>) return null;
    final name = fields['track_name']?.toString().trim();
    return name != null && name.isNotEmpty ? name : null;
  }

  static bool _isSoundCloudUrl(String s) {
    final lower = s.toLowerCase().trim();
    return (lower.contains('soundcloud.com') ||
            lower.contains('on.soundcloud.com') ||
            lower.contains('soundcloud.app.goo.gl')) &&
        (lower.startsWith('http://') || lower.startsWith('https://'));
  }

  static bool _isYouTubeUrl(String s) {
    final lower = s.toLowerCase().trim();
    return (lower.contains('youtube.com') || lower.contains('youtu.be')) &&
        (lower.startsWith('http://') || lower.startsWith('https://'));
  }

  static List<String> _getMediaUrls(Map<String, dynamic> submission, bool Function(String) isMatch) {
    final urls = <String>{};
    void addIfMatch(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      if (isMatch(t)) urls.add(t);
    }
    for (final link in (submission['links'] as List<dynamic>? ?? const [])) {
      addIfMatch(link.toString());
    }
    final fields = submission['fields'];
    if (fields is Map<String, dynamic>) {
      for (final entry in fields.entries) {
        final val = entry.value;
        if (val is! String) continue;
        addIfMatch(val);
      }
    }
    final message = (submission['message'] ?? '').toString();
    if (message.isNotEmpty) {
      final uriPattern = RegExp(
        r'https?://[^\s<>"{}|\\^`\[\]]+',
        caseSensitive: false,
      );
      for (final match in uriPattern.allMatches(message)) {
        addIfMatch(match.group(0)!);
      }
    }
    return urls.toList();
  }

  @override
  Widget build(BuildContext context) {
    final demos = delegate.demoSubmissionsList;
    return RefreshIndicator(
      onRefresh: delegate.loadDemoSubmissions,
      child: demos.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No demo submissions yet.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: demos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = demos[index] as Map<String, dynamic>;
                final id = item['id'] as int?;
                final artistName = (item['artist_name'] ?? '').toString();
                final email = (item['email'] ?? '').toString();
                final genre = (item['genre'] ?? '').toString();
                final city = (item['city'] ?? '').toString();
                final status = (item['status'] ?? 'demo').toString();
                final sentAt = (item['approval_email_sent_at'] ?? '').toString();
                final hasDemoFile = item['has_demo_file'] == true;
                final submittedAt = _formatSubmittedAt(item['created_at']);
                final trackName = _getTrackName(item);
                final soundCloudUrls = _getMediaUrls(item, _isSoundCloudUrl);
                final youtubeUrls = _getMediaUrls(item, _isYouTubeUrl);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    artistName.isEmpty ? email : artistName,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  if (trackName != null && trackName.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      trackName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Chip(
                                  label: Text(status),
                                  labelStyle: const TextStyle(color: Colors.white),
                                  backgroundColor: _statusColor(context, status),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _confirmDeleteDemo(context, delegate, item),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (email.isNotEmpty) Text(email),
                            if (genre.isNotEmpty) Text('Genre: $genre'),
                            if (city.isNotEmpty) Text('City: $city'),
                            if (sentAt.isNotEmpty) Text('Approval sent: $sentAt'),
                            if (submittedAt != null) Text('Submitted: $submittedAt'),
                            if (hasDemoFile && id != null)
                              _DemoMp3DownloadLink(
                                demoId: id,
                                apiClient: delegate.apiClient,
                                token: delegate.token,
                              ),
                            ...soundCloudUrls.map((url) => _MediaLinkChip(label: 'SoundCloud', url: url)),
                            ...youtubeUrls.map((url) => _MediaLinkChip(label: 'YouTube', url: url)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => delegate.showDemoDetailsDialog(item),
                              icon: const Icon(ZalmanimIcons.visibility),
                              label: const Text('Details'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: status == 'approved'
                                  ? null
                                  : () => delegate.showApproveDemoDialog(item),
                              icon: const Icon(ZalmanimIcons.markEmailRead),
                              label: const Text('Approve'),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              onSelected: (value) => delegate.updateDemoStatus(item, value),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'demo', child: Text('Mark as demo')),
                                PopupMenuItem(value: 'in_review', child: Text('Mark in review')),
                                PopupMenuItem(value: 'approved', child: Text('Mark approved')),
                                PopupMenuItem(value: 'pending_release', child: Text('Mark pending release')),
                                PopupMenuItem(value: 'rejected', child: Text('Mark rejected')),
                              ],
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(ZalmanimIcons.moreHoriz),
                                    SizedBox(width: 4),
                                    Text('Status'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Inline download link for demo MP3 in the list. Fetches with auth then triggers browser download.
class _DemoMp3DownloadLink extends StatefulWidget {
  const _DemoMp3DownloadLink({
    required this.demoId,
    required this.apiClient,
    required this.token,
  });

  final int demoId;
  final ApiClient apiClient;
  final String token;

  @override
  State<_DemoMp3DownloadLink> createState() => _DemoMp3DownloadLinkState();
}

class _DemoMp3DownloadLinkState extends State<_DemoMp3DownloadLink> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await widget.apiClient.downloadDemoSubmissionFile(
        token: widget.token,
        id: widget.demoId,
      );
      if (!mounted) return;
      triggerBrowserDownload(bytes, 'demo_${widget.demoId}.mp3');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download started.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _downloading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : TextButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download MP3'),
            ),
    );
  }
}

/// Clickable chip that opens a YouTube or SoundCloud link in the browser.
class _MediaLinkChip extends StatelessWidget {
  const _MediaLinkChip({required this.label, required this.url});

  final String label;
  final String url;

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        label: Text(label),
        avatar: Icon(
          label == 'YouTube' ? Icons.play_circle_outline : Icons.headphones,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: _openUrl,
      ),
    );
  }
}
