import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../application/onboarding_state.dart';

enum _RecordingPhase { requestingPermission, permissionDenied, idle, recording, recorded }

class VoiceRecordingStep extends StatefulWidget {
  const VoiceRecordingStep({super.key});

  @override
  State<VoiceRecordingStep> createState() => _VoiceRecordingStepState();
}

class _VoiceRecordingStepState extends State<VoiceRecordingStep> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  _RecordingPhase _phase = _RecordingPhase.requestingPermission;
  String? _recordingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    // Ask for mic permission only right when the user reaches this step,
    // per the brief -- not at app launch, not earlier in onboarding.
    _requestMicPermission();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
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
    setState(() {
      _phase = _RecordingPhase.recording;
      _recordingPath = path;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() {
      _phase = _RecordingPhase.recorded;
      _recordingPath = path ?? _recordingPath;
    });
  }

  Future<void> _togglePlayback() async {
    if (_recordingPath == null) return;
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }
    await _player.play(DeviceFileSource(_recordingPath!));
    setState(() => _isPlaying = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  void _reRecord() {
    setState(() {
      _phase = _RecordingPhase.idle;
      _recordingPath = null;
      _isPlaying = false;
    });
  }

  Future<void> _upload(OnboardingState state) async {
    final path = _recordingPath;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await state.uploadVoiceRecording(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Record your voice intro')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_phase == _RecordingPhase.requestingPermission) const CircularProgressIndicator(),
            if (_phase == _RecordingPhase.permissionDenied) ...[
              const Text('Microphone access is needed to record your voice intro.'),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _requestMicPermission, child: const Text('Try again')),
              TextButton(onPressed: openAppSettings, child: const Text('Open app settings')),
            ],
            if (_phase == _RecordingPhase.idle)
              FilledButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('Start recording'),
              ),
            if (_phase == _RecordingPhase.recording)
              FilledButton.icon(
                onPressed: _stopRecording,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            if (_phase == _RecordingPhase.recorded) ...[
              IconButton.filled(
                onPressed: _togglePlayback,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                iconSize: 40,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(onPressed: _reRecord, child: const Text('Re-record')),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: state.isLoading ? null : () => _upload(state),
                    child: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Use this recording'),
                  ),
                ],
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
