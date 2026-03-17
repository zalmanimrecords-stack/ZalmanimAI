import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_client.dart';
import '../../../core/zalmanim_icons.dart';

class SignedInArtistsReportDialog extends StatefulWidget {
  const SignedInArtistsReportDialog({
    super.key,
    required this.apiClient,
    required this.token,
    required this.dialogWidth,
  });

  final ApiClient apiClient;
  final String token;
  final double dialogWidth;

  @override
  State<SignedInArtistsReportDialog> createState() =>
      _SignedInArtistsReportDialogState();
}

class _SignedInArtistsReportDialogState
    extends State<SignedInArtistsReportDialog> {
  bool _loading = true;
  String? _error;
  List<dynamic> _artists = const [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.apiClient.fetchArtistsSignedIn(widget.token);
      if (!mounted) return;
      setState(() {
        _artists = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _reportToCsv() {
    final buffer = StringBuffer('Artist ID,Name,Email,Active,Last Login\n');
    for (final item in _artists) {
      final artist = item as Map<String, dynamic>;
      buffer.writeln([
        _csvValue('${artist['id'] ?? ''}'),
        _csvValue((artist['name'] ?? '').toString()),
        _csvValue((artist['email'] ?? '').toString()),
        _csvValue((artist['is_active'] ?? '').toString()),
        _csvValue(_formatIso((artist['last_login_at'] ?? '').toString())),
      ].join(','));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Artists signed in'),
      content: SizedBox(
        width: widget.dialogWidth,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _loadReport,
                        icon: const Icon(ZalmanimIcons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_artists.length} artist(s) have already signed in to the artist portal.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _artists.isEmpty
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: _reportToCsv()),
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Report copied as CSV.'),
                                      ),
                                    );
                                  },
                            icon: const Icon(ZalmanimIcons.copy, size: 18),
                            label: const Text('Copy CSV'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: _artists.isEmpty
                            ? const Center(
                                child: Text(
                                  'No artists have signed in yet.',
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: _artists.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final artist =
                                      _artists[index] as Map<String, dynamic>;
                                  final active =
                                      artist['is_active'] as bool? ?? true;
                                  final lastLogin = artist['last_login_at'];
                                  return Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        child: Text(
                                          ((artist['name'] ?? '?')
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty
                                              ? (artist['name'] as String)
                                                  .trim()[0]
                                                  .toUpperCase()
                                              : '?'),
                                        ),
                                      ),
                                      title: Text(
                                        (artist['name'] ?? '').toString(),
                                      ),
                                      subtitle: Text(
                                        '${(artist['email'] ?? '').toString()} • ${lastLogin != null ? _formatIso(lastLogin.toString()) : '-'}',
                                      ),
                                      trailing: Chip(
                                        label: Text(
                                          active ? 'Active' : 'Inactive',
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : _loadReport,
          child: const Text('Refresh'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _csvValue(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String _formatIso(String iso) {
  try {
    final dt = DateTime.tryParse(iso);
    if (dt != null) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  } catch (_) {}
  return iso;
}
