import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/voice_clip_player.dart';
import '../application/onboarding_state.dart';
import 'onboarding_progress.dart';

enum _RecordingPhase { requestingPermission, permissionDenied, idle, recording, recorded }

class VoiceRecordingStep extends StatefulWidget {
  const VoiceRecordingStep({super.key});

  @override
  State<VoiceRecordingStep> createState() => _VoiceRecordingStepState();
}

class _VoiceRecordingStepState extends State<VoiceRecordingStep> {
  final _recorder = AudioRecorder();
  _RecordingPhase _phase = _RecordingPhase.requestingPermission;
  String? _recordingPath;

  // Display-only: the elapsed time shown while recording.
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Ask for mic permission only right when the user reaches this step,
    // per the brief -- not at app launch, not earlier in onboarding.
    _requestMicPermission();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    setState(() {
      _phase = status.isGranted ? _RecordingPhase.idle : _RecordingPhase.permissionDenied;
    });
  }

  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/lolly_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _elapsed = Duration.zero;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
    setState(() {
      _phase = _RecordingPhase.recording;
      _recordingPath = path;
    });
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _phase = _RecordingPhase.recorded;
      _recordingPath = path ?? _recordingPath;
    });
  }

  void _reRecord() {
    setState(() {
      _phase = _RecordingPhase.idle;
      _recordingPath = null;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _upload(OnboardingState state) async {
    final path = _recordingPath;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await state.uploadVoiceRecording(bytes);
  }

  String get _elapsedLabel {
    final m = _elapsed.inMinutes.toString();
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final textTheme = Theme.of(context).textTheme;
    final recorded = _phase == _RecordingPhase.recorded;

    return OnboardingScaffold(
      step: onboardingStepNumber(state.currentStep),
      totalSteps: kOnboardingStepCount,
      emoji: '🎙️',
      title: 'Let them hear you',
      subtitle: 'A short voice intro. Before anyone sees you, this is how they get to know you.',
      errorMessage: state.errorMessage,
      primaryLabel: recorded ? 'Use this recording' : null,
      primaryIcon: Icons.check_rounded,
      loading: state.isLoading,
      onPrimary: recorded ? () => _upload(state) : null,
      secondary: recorded
          ? TextButton.icon(
              onPressed: state.isLoading ? null : _reRecord,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Record again'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The tip only matters before recording; once there's a take,
          // drop it so the player and actions fit without scrolling.
          if (_phase != _RecordingPhase.recorded) ...[
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Not sure what to say? ', style: textTheme.titleSmall),
                          const TextSpan(text: 'Your perfect Sunday, something you geek out about, what makes you laugh.'),
                        ],
                      ),
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isCompactHeight(context) ? AppSpacing.sm : AppSpacing.lg),
          ],
          _buildRecorder(context),
        ],
      ),
    );
  }

  Widget _buildRecorder(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    switch (_phase) {
      case _RecordingPhase.requestingPermission:
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        );

      case _RecordingPhase.permissionDenied:
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mic_off_rounded, size: 40, color: AppTheme.coralLight),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Microphone access is needed to record your voice intro.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _requestMicPermission, child: const Text('Try again')),
              const TextButton(onPressed: openAppSettings, child: Text('Open app settings')),
            ],
          ),
        );

      case _RecordingPhase.idle:
      case _RecordingPhase.recording:
        final recording = _phase == _RecordingPhase.recording;
        return Column(
          children: [
            _MicOrb(
              recording: recording,
              size: isCompactHeight(context) ? 104 : 124,
              onTap: recording ? _stopRecording : _startRecording,
            ),
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: recording
                  ? Column(
                      key: const ValueKey('rec'),
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(color: Color(0xFFFF4D6D), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(_elapsedLabel, style: textTheme.headlineSmall),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const VoiceWaveform(active: true, barCount: 21, height: 44, barWidth: 4, gap: 4, color: AppTheme.coral),
                        const SizedBox(height: AppSpacing.md),
                        Text('Tap to stop', style: textTheme.bodyMedium),
                      ],
                    )
                  : Text(
                      'Tap the mic to start recording',
                      key: const ValueKey('idle'),
                      style: textTheme.titleMedium?.copyWith(color: AppTheme.textMuted),
                    ),
            ),
          ],
        );

      case _RecordingPhase.recorded:
        return GlassCard(
          selected: true,
          child: Column(
            children: [
              Text('Your voice intro', style: textTheme.titleMedium),
              const SizedBox(height: 2),
              Text('$_elapsedLabel · give it a listen', style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.md),
              VoiceClipPlayer(source: DeviceFileSource(_recordingPath!)),
            ],
          ),
        );
    }
  }
}

/// The big record button: a Bloom-gradient orb with a breathing halo
/// while recording.
class _MicOrb extends StatefulWidget {
  const _MicOrb({required this.recording, required this.onTap, this.size = 124});

  final bool recording;
  final VoidCallback onTap;
  final double size;

  @override
  State<_MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<_MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_MicOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recording != widget.recording) _sync();
  }

  void _sync() {
    if (widget.recording) {
      _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // Room for the halo to grow to 1.5x without clipping.
    return SizedBox(
      width: size * 1.5,
      height: size * 1.5,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.recording)
                for (final offset in const [0.0, 0.5])
                  Builder(builder: (context) {
                    final p = (t + offset) % 1;
                    return Container(
                      width: size * (1 + 0.5 * p),
                      height: size * (1 + 0.5 * p),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.magenta.withValues(alpha: 0.5 * (1 - p)), width: 2),
                      ),
                    );
                  }),
              child!,
            ],
          );
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: brandGradient(),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.magenta.withValues(alpha: widget.recording ? 0.7 : 0.5),
                  blurRadius: widget.recording ? 50 : 36,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Icon(
              widget.recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 56,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
