import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api_client.dart';
import 'file_download.dart';

/// Label + value row for the demo details dialog (selectable value).
class DemoSubmissionInfoRow extends StatelessWidget {
  const DemoSubmissionInfoRow(
    this.label,
    this.value, {
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }
}

/// Fetches the demo MP3 with auth, then triggers a browser download (web).
class DemoSubmissionMp3DownloadButton extends StatefulWidget {
  const DemoSubmissionMp3DownloadButton({
    super.key,
    required this.demoId,
    required this.apiClient,
    required this.token,
  });

  final int demoId;
  final ApiClient apiClient;
  final String token;

  @override
  State<DemoSubmissionMp3DownloadButton> createState() =>
      _DemoSubmissionMp3DownloadButtonState();
}

class _DemoSubmissionMp3DownloadButtonState
    extends State<DemoSubmissionMp3DownloadButton> {
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
      triggerBrowserDownload(
        bytes,
        'demo_${widget.demoId}.mp3',
        mimeType: 'audio/mpeg',
      );
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
      padding: const EdgeInsets.only(top: 4),
      child: FilledButton.icon(
        onPressed: _downloading ? null : _download,
        icon: _downloading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.download, size: 20),
        label: Text(_downloading ? 'Downloading...' : 'Download MP3'),
      ),
    );
  }
}

/// SoundCloud embed player for a track URL (used in demo details dialog).
class DemoSoundCloudEmbed extends StatefulWidget {
  const DemoSoundCloudEmbed({super.key, required this.soundCloudUrl});

  final String soundCloudUrl;

  @override
  State<DemoSoundCloudEmbed> createState() => _DemoSoundCloudEmbedState();
}

class _DemoSoundCloudEmbedState extends State<DemoSoundCloudEmbed> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final encoded = Uri.encodeComponent(widget.soundCloudUrl);
    final embedUrl =
        'https://w.soundcloud.com/player/?url=$encoded&color=%23ff5500&auto_play=false&hide_related=false&show_comments=true&show_user=true&show_reposts=false&show_teaser=true';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 166,
      width: double.infinity,
      child: WebViewWidget(controller: _controller),
    );
  }
}
