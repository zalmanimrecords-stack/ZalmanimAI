// Non-web demo MP3 player using just_audio (mobile/desktop).
// Not used in web build so dart2js never compiles just_audio for web.

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Inline audio player for demo MP3 (streams from admin download URL with auth).
class DemoMp3PlayerWidget extends StatefulWidget {
  const DemoMp3PlayerWidget({super.key, required this.downloadUrl, required this.token});

  final String downloadUrl;
  final String token;

  @override
  State<DemoMp3PlayerWidget> createState() => _DemoMp3PlayerWidgetIoState();
}

class _DemoMp3PlayerWidgetIoState extends State<DemoMp3PlayerWidget> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _player.setAudioSource(
      AudioSource.uri(
        Uri.parse(widget.downloadUrl),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ),
    ).catchError((Object e) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(_player.playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  iconSize: 48,
                  onPressed: () async {
                    if (_player.playing) {
                      await _player.pause();
                    } else {
                      await _player.play();
                    }
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snap) {
                      final position = snap.data ?? Duration.zero;
                      final duration = _player.duration ?? Duration.zero;
                      final posSec = position.inSeconds;
                      final durSec = duration.inSeconds > 0 ? duration.inSeconds : 1;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            ),
                            child: Slider(
                              value: posSec.clamp(0, durSec).toDouble(),
                              max: durSec.toDouble(),
                              onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
                            ),
                          ),
                          Text(
                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final state = snap.data;
                if (state?.processingState == ProcessingState.failed) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      'Failed to load audio: ${_player.playerState.processingState}',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}
