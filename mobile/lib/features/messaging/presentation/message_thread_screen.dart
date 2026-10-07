import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/notifications/push_notifications.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/voice_clip_player.dart';
import '../../trust_safety/domain/report_reason.dart';
import '../../trust_safety/presentation/trust_safety_actions.dart';
import '../application/message_thread_state.dart';
import '../domain/message.dart';

const _maxVoiceMessageSeconds = 60;

/// One open conversation. Owns the voice-recording widget lifecycle
/// itself (mirrors voice_recording_step.dart's pattern -- the recorder is
/// UI-lifecycle-bound, not business state, so it doesn't belong on
/// MessageThreadState); everything past "here are the raw bytes and the
/// duration" goes through the state.
class MessageThreadScreen extends StatelessWidget {
  const MessageThreadScreen({
    super.key,
    required this.connectionId,
    required this.currentUserId,
    required this.otherUserId,
    this.otherDisplayName,
  });

  final String connectionId;
  final String currentUserId;
  final String otherUserId;
  final String? otherDisplayName;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MessageThreadState(connectionId: connectionId, currentUserId: currentUserId)..load(),
      child: _MessageThreadBody(
        connectionId: connectionId,
        title: otherDisplayName ?? 'Chat',
        otherUserId: otherUserId,
      ),
    );
  }
}

class _MessageThreadBody extends StatefulWidget {
  const _MessageThreadBody({required this.connectionId, required this.title, required this.otherUserId});

  final String connectionId;
  final String title;
  final String otherUserId;

  @override
  State<_MessageThreadBody> createState() => _MessageThreadBodyState();
}

enum _RecordingPhase { idle, requestingPermission, permissionDenied, recording }

class _MessageThreadBodyState extends State<_MessageThreadBody> {
  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  final _scrollController = ScrollController();

  _RecordingPhase _recordingPhase = _RecordingPhase.idle;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _autoStopTimer;

  // WP7: a foreground push for THIS thread is redundant while it is on
  // screen (the socket already rendered the message) -- tell the push
  // layer which thread that is, and un-tell it on the way out.
  @override
  void initState() {
    super.initState();
    PushNotifications.instance.activeConnectionId = widget.connectionId;
  }

  @override
  void dispose() {
    if (PushNotifications.instance.activeConnectionId == widget.connectionId) {
      PushNotifications.instance.activeConnectionId = null;
    }
    _textController.dispose();
    _recorder.dispose();
    _scrollController.dispose();
    _autoStopTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    await context.read<MessageThreadState>().sendText(text);
  }

  Future<void> _startRecording() async {
    setState(() => _recordingPhase = _RecordingPhase.requestingPermission);
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _recordingPhase = _RecordingPhase.permissionDenied);
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/lolly_voice_msg_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _autoStopTimer = Timer(const Duration(seconds: _maxVoiceMessageSeconds), _stopAndSendRecording);
    setState(() {
      _recordingPhase = _RecordingPhase.recording;
      _recordingPath = path;
      _recordingStartedAt = DateTime.now();
    });
  }

  Future<void> _stopAndSendRecording() async {
    _autoStopTimer?.cancel();
    final startedAt = _recordingStartedAt;
    final path = await _recorder.stop() ?? _recordingPath;
    setState(() => _recordingPhase = _RecordingPhase.idle);
    if (path == null || startedAt == null) return;

    final durationSec = DateTime.now().difference(startedAt).inSeconds.clamp(1, _maxVoiceMessageSeconds);
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    await context.read<MessageThreadState>().sendVoice(bytes, contentType: 'audio/mp4', durationSec: durationSec);
  }

  Future<void> _handleBlock(BuildContext context) async {
    final blocked = await confirmAndBlockUser(context, userId: widget.otherUserId);
    // The blocked match disappears from the conversation list on its own
    // (backend's listConversations only returns AUTHENTICATED_MATCH/
    // ACTIVE connections, and blocking forces BLOCKED) -- popping back
    // there is enough; no special "removed" state needed in this screen
    // itself since it's gone the moment you leave it.
    if (blocked && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MessageThreadState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'report') {
                showReportDialog(
                  context,
                  reportedUserId: widget.otherUserId,
                  reportContext: ReportContext.connection,
                  contextId: state.connectionId,
                );
              } else if (value == 'block') {
                _handleBlock(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report conversation')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(context, state)),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(state.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          _buildComposer(context, state),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, MessageThreadState state) {
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.messages.isEmpty) {
      return Center(
        child: Text(
          'Say hello!',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: state.messages.length + (state.hasMoreHistory ? 1 : 0),
      itemBuilder: (context, index) {
        if (state.hasMoreHistory && index == 0) {
          return Center(
            child: TextButton(onPressed: state.loadOlder, child: const Text('Load earlier messages')),
          );
        }
        final message = state.messages[index - (state.hasMoreHistory ? 1 : 0)];
        return _MessageBubble(message: message, isMine: message.isMine(state.currentUserId));
      },
    );
  }

  Widget _buildComposer(BuildContext context, MessageThreadState state) {
    if (_recordingPhase == _RecordingPhase.permissionDenied) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text('Microphone access is needed for voice messages.')),
            TextButton(onPressed: openAppSettings, child: Text('Settings')),
          ],
        ),
      );
    }

    if (_recordingPhase == _RecordingPhase.recording) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.fiber_manual_record, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('Recording... (sends automatically at 60s)')),
            IconButton(
              icon: Icon(Icons.stop_circle_rounded, color: Theme.of(context).colorScheme.error),
              onPressed: _stopAndSendRecording,
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !state.isSending,
                decoration: InputDecoration(
                  hintText: 'Message',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: 'Record a voice message',
              icon: const Icon(Icons.mic_rounded),
              onPressed: state.isSending ? null : _startRecording,
            ),
            IconButton.filled(
              tooltip: 'Send',
              icon: state.isSending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              onPressed: state.isSending ? null : _sendText,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isMine ? scheme.primary : scheme.surfaceContainerHigh;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.lg),
      topRight: const Radius.circular(AppRadius.lg),
      bottomLeft: Radius.circular(isMine ? AppRadius.lg : AppRadius.xs),
      bottomRight: Radius.circular(isMine ? AppRadius.xs : AppRadius.lg),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(color: color, borderRadius: radius),
        child: message.type == MessageType.voice && message.audioUrl != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VoiceClipPlayer(
                    source: UrlSource(message.audioUrl!),
                    iconSize: 22,
                    tint: isMine ? scheme.onPrimary : null,
                  ),
                  const SizedBox(width: 8),
                  Text('${message.audioDurationSec ?? 0}s', style: TextStyle(color: foreground)),
                  if (isMine) _StatusIcon(message: message),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: Text(message.textContent ?? '', style: TextStyle(color: foreground, height: 1.35))),
                  if (isMine) _StatusIcon(message: message),
                ],
              ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final icon = message.readAt != null
        ? Icons.done_all
        : message.deliveredAt != null
            ? Icons.done_all
            : Icons.done;
    final onBubble = Theme.of(context).colorScheme.onPrimary;
    final color = message.readAt != null ? AppTheme.peach : onBubble.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
