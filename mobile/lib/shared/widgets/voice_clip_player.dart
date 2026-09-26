import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Play/pause control for a single audio clip -- extracted so playback
/// lifecycle (start/stop, completion handling, disposal) lives in one
/// place instead of being duplicated between WP2's own-recording preview
/// (a local file, played via DeviceFileSource) and WP3's discovery
/// candidate card (a remote signed URL, played via UrlSource). Both pass
/// whatever audioplayers Source fits their case; this widget doesn't care
/// which.
class VoiceClipPlayer extends StatefulWidget {
  const VoiceClipPlayer({super.key, required this.source, this.iconSize = 40});

  final Source source;
  final double iconSize;

  @override
  State<VoiceClipPlayer> createState() => _VoiceClipPlayerState();
}

class _VoiceClipPlayerState extends State<VoiceClipPlayer> {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    await _player.play(widget.source);
    if (!mounted) return;
    setState(() => _isPlaying = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: _toggle,
      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
      iconSize: widget.iconSize,
    );
  }
}
