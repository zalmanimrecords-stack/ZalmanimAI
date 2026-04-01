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

  _MinisitePalette _paletteFor(String theme) {
    switch (theme) {
      case 'sunset':
        return const _MinisitePalette(
          background: LinearGradient(
            colors: [Color(0xFFFFF1E7), Color(0xFFFFD4BD), Color(0xFFF28D6B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          card: Color(0xCCFFF8F2),
          primary: Color(0xFFB14D29),
          text: Color(0xFF4E271B),
          muted: Color(0xFF7B5649),
        );
      case 'mono':
        return const _MinisitePalette(
          background: LinearGradient(
            colors: [Color(0xFFF4F4F4), Color(0xFFE3E3E3), Color(0xFFD2D2D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          card: Color(0xCCFFFFFF),
          primary: Color(0xFF202020),
          text: Color(0xFF141414),
          muted: Color(0xFF626262),
        );
      default:
        return const _MinisitePalette(
          background: LinearGradient(
            colors: [Color(0xFFE9F4FF), Color(0xFFCCEBF1), Color(0xFF97D9D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          card: Color(0xCCF9FFFF),
          primary: Color(0xFF0D6F73),
          text: Color(0xFF123C47),
          muted: Color(0xFF476771),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        body: LoadingView(primary: Theme.of(context).colorScheme.primary),
      );
    }

    if (error != null) {
      return Scaffold(
        body: ErrorView(message: error!, onRetry: _load),
      );
    }

    final d = data!;
    final palette = _paletteFor(d.theme);
    final name = d.name;
    final profileImageUrl = d.profileImageUrl;
    final logoUrl = d.logoUrl;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.background),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heroCard(context, d, palette, name, profileImageUrl, logoUrl),
                      if (d.links.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionCard(
                          context,
                          palette,
                          title: 'Listen, follow, connect',
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: d.links.map((link) {
                              return SizedBox(
                                width: 250,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: palette.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () => openUrlOrCopy(context, link.url),
                                  child: Text(link.label, textAlign: TextAlign.center),
                                ),
                              );
                            }).toList(growable: false),
                          ),
                        ),
                      ],
                      if (d.galleryImageUrls.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionCard(
                          context,
                          palette,
                          title: 'Gallery',
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 720
                                  ? 3
                                  : constraints.maxWidth >= 460
                                      ? 2
                                      : 1;
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: d.galleryImageUrls.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.05,
                                ),
                                itemBuilder: (context, index) {
                                  final imageUrl = d.galleryImageUrls[index];
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: palette.primary.withValues(alpha: 0.08),
                                        child: Icon(Icons.broken_image_outlined, color: palette.primary),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                      if (d.releases.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionCard(
                          context,
                          palette,
                          title: 'Releases',
                          child: Column(
                            children: d.releases.asMap().entries.map((entry) {
                              final release = entry.value;
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: entry.key == d.releases.length - 1 ? 0 : 10,
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  tileColor: Colors.white.withValues(alpha: 0.46),
                                  title: Text(
                                    release.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: palette.text,
                                    ),
                                  ),
                                  subtitle: Text(
                                    release.url == null ? 'Link coming soon' : 'Open release page',
                                    style: TextStyle(color: palette.muted),
                                  ),
                                  trailing: Icon(Icons.open_in_new, color: palette.primary),
                                  onTap: release.url == null
                                      ? null
                                      : () => openUrlOrCopy(context, release.url!),
                                ),
                              );
                            }).toList(growable: false),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroCard(
    BuildContext context,
    LinktreeOut data,
    _MinisitePalette palette,
    String name,
    String? profileImageUrl,
    String? logoUrl,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          if (profileImageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(56),
              child: Image.network(
                profileImageUrl,
                width: 112,
                height: 112,
                fit: BoxFit.cover,
                cacheWidth: 224,
                cacheHeight: 224,
                errorBuilder: (_, __, ___) => _avatarCircle(palette.primary, name),
              ),
            )
          else
            _avatarCircle(palette.primary, name),
          const SizedBox(height: 18),
          if (logoUrl != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Image.network(
                logoUrl,
                height: 44,
                fit: BoxFit.contain,
                cacheHeight: 88,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Text(
            name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                ),
            textAlign: TextAlign.center,
          ),
          if (data.headline != null) ...[
            const SizedBox(height: 10),
            Text(
              data.headline!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.primary,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (data.bio != null) ...[
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                data.bio!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.55,
                      color: palette.muted,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context,
    _MinisitePalette palette, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _avatarCircle(Color primary, String name) {
    return CircleAvatar(
      radius: 56,
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

class _MinisitePalette {
  const _MinisitePalette({
    required this.background,
    required this.card,
    required this.primary,
    required this.text,
    required this.muted,
  });

  final LinearGradient background;
  final Color card;
  final Color primary;
  final Color text;
  final Color muted;
}
