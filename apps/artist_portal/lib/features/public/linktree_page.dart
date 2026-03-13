import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/zalmanim_icons.dart';

/// Public styled Linktree-style page for an artist (no login).
/// Route: /l/{artistId}
class LinktreePage extends StatefulWidget {
  const LinktreePage({
    super.key,
    required this.apiClient,
    required this.artistId,
  });

  final ApiClient apiClient;
  final int artistId;

  @override
  State<LinktreePage> createState() => _LinktreePageState();
}

class _LinktreePageState extends State<LinktreePage> {
  bool loading = true;
  String? error;
  String? name;
  List<Map<String, dynamic>> links = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.apiClient.fetchPublicLinktree(widget.artistId);
      final linksList = data['links'];
      setState(() {
        name = data['name']?.toString() ?? 'Artist';
        final list = linksList is List ? linksList : <dynamic>[];
        links = list
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .where((e) => (e['label'] ?? e['url']) != null)
            .toList();
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primary),
              const SizedBox(height: 16),
              Text(
                AppConfig.labelName,
                style: TextStyle(color: primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ZalmanimIcons.errorOutline, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 16),
                SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(ZalmanimIcons.copy),
                  tooltip: 'Copy',
                  onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 48,
                backgroundColor: primary.withValues(alpha: 0.2),
                child: Text(
                  (name ?? '?').isNotEmpty ? (name!.substring(0, 1).toUpperCase()) : '?',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name ?? 'Artist',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? null : Colors.grey[800],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (links.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No links yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              else
                ...links.map((link) {
                  final label = link['label']?.toString() ?? 'Link';
                  final url = link['url']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: url.isEmpty ? null : () => _openUrl(url),
                        child: Text(label),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Link copied: $url')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link copied: $url')),
        );
      }
    }
  }
}
