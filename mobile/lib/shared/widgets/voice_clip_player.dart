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

  /// Override the control's colour family -- e.g. white when the player
  /// sits on a gradient chat bubble (a solid [tint] disc with a magenta
  /// glyph). Defaults to the Bloom-gradient disc with a coral waveform.
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
    final tint = widget.tint;
    final tinted = tint != null;
    // Same footprint as the old IconButton.filled: glyph + 8px each side.
    final diameter = widget.iconSize + 16;
    final large = widget.iconSize >= 36;
    final waveColor = tinted
        ? tint.withValues(alpha: _isPlaying ? 1 : 0.6)
        : _isPlaying
            ? AppTheme.coral
            : AppTheme.coralLight.withValues(alpha: 0.5);

    final button = Tooltip(
      message: _isPlaying ? 'Stop' : 'Play',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint,
          gradient: tinted ? null : brandGradient(),
          boxShadow: tinted
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.magenta.withValues(alpha: _isPlaying ? 0.6 : 0.4),
                    blurRadius: diameter * (_isPlaying ? 0.6 : 0.4),
                    spreadRadius: -diameter * 0.12,
                    offset: Offset(0, diameter * 0.12),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: widget.iconSize,
              color: tinted ? AppTheme.magenta : Colors.white,
            ),
          ),
        ),
      ),
    );
    if (!widget.showWaveform) return button;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        SizedBox(width: large ? AppSpacing.md : AppSpacing.sm),
        VoiceWaveform(
          active: _isPlaying,
          barCount: large ? 11 : 7,
          height: widget.iconSize * 0.9,
          barWidth: (widget.iconSize * 0.1).clamp(3, 6),
          gap: 3,
          color: waveColor,
        ),
      ],
    );
  }
}
