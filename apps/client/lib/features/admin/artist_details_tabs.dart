import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';

/// Read-only artist summary for the artist details dialog (Info tab).
class ArtistDetailsInfoTab extends StatelessWidget {
  const ArtistDetailsInfoTab({
    super.key,
    required this.artistMap,
    required this.onEdit,
  });

  final Map<String, dynamic> artistMap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final extra = artistMap['extra'] as Map<String, dynamic>? ?? {};
    final name = (artistMap['name'] ?? '').toString();
    final email = (artistMap['email'] ?? '').toString();
    final notes = (artistMap['notes'] ?? '').toString();
    final brand = (extra['artist_brand'] ?? name).toString();
    final fullName = (extra['full_name'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _infoRow('Brand', brand),
          if (fullName.isNotEmpty) _infoRow('Full name', fullName),
          _infoRow('Email', email),
          if (notes.isNotEmpty) _infoRow('Notes', notes),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(ZalmanimIcons.edit, size: 18),
            label: const Text('Edit artist'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

/// Activity log list for the artist details dialog (Logs tab).
class ArtistDetailsLogsTab extends StatefulWidget {
  const ArtistDetailsLogsTab({
    super.key,
    required this.apiClient,
    required this.token,
    required this.artistId,
  });

  final ApiClient apiClient;
  final String token;
  final int artistId;

  @override
  State<ArtistDetailsLogsTab> createState() => _ArtistDetailsLogsTabState();
}

class _ArtistDetailsLogsTabState extends State<ArtistDetailsLogsTab> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.apiClient
          .fetchArtistActivity(widget.token, widget.artistId);
      if (!mounted) return;
      setState(() {
        _logs = list;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('No activity logged yet.'));
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _logs.length,
      itemBuilder: (_, i) {
        final log = _logs[i] as Map<String, dynamic>;
        final type = (log['activity_type'] ?? '').toString();
        final details = (log['details'] ?? '').toString();
        final createdAt = log['created_at'];
        String dateStr = '';
        if (createdAt != null) {
          try {
            final dt = DateTime.parse(createdAt.toString());
            dateStr =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          } catch (_) {
            dateStr = createdAt.toString();
          }
        }
        return ListTile(
          leading: Icon(
            type == 'reminder_email'
                ? ZalmanimIcons.email
                : ZalmanimIcons.history,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            type == 'reminder_email' ? 'Reminder email sent' : type,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(dateStr, style: const TextStyle(fontSize: 12)),
              if (details.isNotEmpty)
                SelectableText(details, style: const TextStyle(fontSize: 11)),
            ],
          ),
          dense: true,
        );
      },
    );
  }
}
