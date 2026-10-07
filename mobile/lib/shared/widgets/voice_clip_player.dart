import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/branding.dart';

/// Play/pause control for a single audio clip, with the app's waveform cue
/// breathing beside it while the clip plays. Extracted so playback
/// lifecycle (start/stop, completion handling, disposal) lives in one
/// place instead of being duplicated between WP2's own-recording preview
/// (a local file, played via DeviceFileSource), WP3's discovery candidate
/// card and WP5's voice bubbles (remote signed URLs, played via
/// UrlSource). Both pass whatever audioplayers Source fits their case.
class VoiceClipPlayer extends StatefulWidget {
  const VoiceClipPlayer({
    super.key,
    required this.source,
    this.iconSize = 40,
    this.showWaveform = true,
    this.tint,
  });

  final Source source;
  final double iconSize;

  /// Hide the waveform where there's no room (dense rows).
  final bool showWaveform;

  /// Override the control's colour family -- e.g. `onPrimary` when the
  /// player sits on a primary-coloured chat bubble. Defaults to the
  /// theme's primary, switching to the coral accent while playing.
  final Color? tint;

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
    final scheme = Theme.of(context).colorScheme;
    final tinted = widget.tint != null;
    final background = tinted
        ? widget.tint!
        : _isPlaying
            ? scheme.tertiary
            : scheme.primary;
    final foreground = tinted ? scheme.primary : Colors.white;
    final waveColor = tinted
        ? widget.tint!.withValues(alpha: _isPlaying ? 1 : 0.6)
        : _isPlaying
            ? scheme.tertiary
            : scheme.primary.withValues(alpha: 0.45);

    final button = IconButton.filled(
      onPressed: _toggle,
      tooltip: _isPlaying ? 'Stop' : 'Play',
      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
      iconSize: widget.iconSize,
      style: IconButton.styleFrom(backgroundColor: background, foregroundColor: foreground),
    );
    if (!widget.showWaveform) return button;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(width: AppSpacing.sm),
        VoiceWaveform(
          active: _isPlaying,
          height: widget.iconSize * 0.9,
          barWidth: (widget.iconSize * 0.1).clamp(3, 6),
          gap: 3,
          color: waveColor,
        ),
      ],
    );
  }
}
