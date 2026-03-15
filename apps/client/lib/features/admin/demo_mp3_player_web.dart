// Web-only demo MP3 player. Uses browser Audio element + fetch with auth.
// No just_audio so the web build compiles with dart2js without plugin issues.

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Inline audio player for demo MP3 on web: fetches with auth, plays via HTML Audio.
class DemoMp3PlayerWidget extends StatefulWidget {
  const DemoMp3PlayerWidget({super.key, required this.downloadUrl, required this.token});

  final String downloadUrl;
  final String token;

  @override
  State<DemoMp3PlayerWidget> createState() => _DemoMp3PlayerWidgetWebState();
}

class _DemoMp3PlayerWidgetWebState extends State<DemoMp3PlayerWidget> {
  static int _nextId = 0;
  static final Map<int, html.AudioElement> _elements = {};

  late final int _id;
  String? _objectUrl;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    final viewType = 'demo-mp3-player-$_id';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final audio = html.AudioElement()
        ..controls = true
        ..style.width = '100%';
      _elements[_id] = audio;
      return audio;
    });
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    try {
      final response = await http.get(
        Uri.parse(widget.downloadUrl),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Failed to load audio (${response.statusCode})';
        });
        return;
      }
      final blob = html.Blob([response.bodyBytes], 'audio/mpeg');
      final url = html.Url.createObjectUrlFromBlob(blob);
      _objectUrl = url;
      final audio = _elements[_id];
      if (audio != null && mounted) {
        audio.src = url;
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    if (_objectUrl != null) {
      html.Url.revokeObjectUrl(_objectUrl!);
    }
    _elements.remove(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('Loading audio...', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _error!,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 40,
          child: HtmlElementView(viewType: 'demo-mp3-player-$_id'),
        ),
      ),
    );
  }
}
