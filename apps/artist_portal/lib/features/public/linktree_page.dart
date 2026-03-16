import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/linktree_models.dart';
import '../../core/loading_error_widgets.dart';
import '../../core/url_launcher_util.dart';

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
  LinktreeOut? data;

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
      final result = await widget.apiClient.fetchPublicLinktree(widget.artistId);
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  static String _avatarInitial(String? name) {
    final s = name ?? '';
    return s.isEmpty ? '?' : s.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (loading) {
      return Scaffold(
        body: LoadingView(primary: primary),
      );
    }

    if (error != null) {
      return Scaffold(
        body: ErrorView(message: error!, onRetry: _load),
      );
    }

    final d = data!;
    final name = d.name;
    final profileImageUrl = d.profileImageUrl;
    final logoUrl = d.logoUrl;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                const SizedBox(height: 24),
                if (profileImageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(48),
                    child: Image.network(
                      profileImageUrl,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      cacheHeight: 192,
                      errorBuilder: (_, __, ___) => _avatarCircle(primary, name),
                    ),
                  )
                else
                  _avatarCircle(primary, name),
                const SizedBox(height: 16),
                if (logoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Image.network(
                      logoUrl,
                      height: 40,
                      fit: BoxFit.contain,
                      cacheHeight: 80,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? null : Colors.grey[800],
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (d.links.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No links yet.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                else
                  ...d.links.asMap().entries.map((entry) {
                    final link = entry.value;
                    return Padding(
                      key: ValueKey<String>(link.url),
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
                          onPressed: link.url.isEmpty
                              ? null
                              : () => openUrlOrCopy(context, link.url),
                          child: Text(link.label),
                        ),
                      ),
                    );
                  }),
                if (d.releases.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Releases',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? null : Colors.grey[800],
                        ),
                  ),
                  const SizedBox(height: 12),
                  ...d.releases.asMap().entries.map((entry) {
                    final r = entry.value;
                    final index = entry.key;
                    return Padding(
                      key: ValueKey<String>('${r.title}-$index'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: r.url != null && r.url!.isNotEmpty
                              ? () => openUrlOrCopy(context, r.url!)
                              : null,
                          child: Text(r.title),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarCircle(Color primary, String name) {
    return CircleAvatar(
      radius: 48,
      backgroundColor: primary.withValues(alpha: 0.2),
      child: Text(
        _avatarInitial(name),
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: primary,
        ),
      ),
    );
  }
}
