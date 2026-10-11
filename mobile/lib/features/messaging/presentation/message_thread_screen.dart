import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/notifications/push_notifications.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/voice_clip_player.dart';
import '../../trust_safety/domain/report_reason.dart';
import '../../trust_safety/presentation/trust_safety_actions.dart';
import '../application/message_thread_state.dart';
import '../domain/message.dart';
import '../../../shared/widgets/media_sources.dart';

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
      backgroundColor: AppTheme.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _TitleAvatar(name: widget.title),
            const SizedBox(width: AppSpacing.sm + 4),
            Flexible(
              child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: AppTheme.ink.withValues(alpha: 0.72),
            border: const Border(bottom: BorderSide(color: AppTheme.stroke)),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
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
      body: AuroraBackground(
        intensity: 0.4,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildMessageList(context, state)),
              if (state.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
                  child: ErrorBanner(state.errorMessage!),
                ),
              _buildComposer(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, MessageThreadState state) {
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.messages.isEmpty) {
      final textTheme = Theme.of(context).textTheme;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LollyMark(size: 72),
              const SizedBox(height: AppSpacing.md),
              Text('Say hello!', style: textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'You heard each other first. A voice note is a great opener.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md - 4, AppSpacing.sm, AppSpacing.md - 4, AppSpacing.sm),
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

  /// The rounded composer bar every phase shares, so swapping between
  /// typing / recording / permission-denied doesn't jump the layout.
  Widget _composerShell({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm + 2, AppSpacing.xs, AppSpacing.sm + 2, AppSpacing.sm + 2),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface1.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppTheme.stroke),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildComposer(BuildContext context, MessageThreadState state) {
    if (_recordingPhase == _RecordingPhase.permissionDenied) {
      return _composerShell(
        child: const Row(
          children: [
            SizedBox(width: AppSpacing.sm + 2),
            Icon(Icons.mic_off_rounded, color: AppTheme.textMuted, size: 20),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Microphone access is needed for voice messages.')),
            TextButton(onPressed: openAppSettings, child: Text('Settings')),
          ],
        ),
      );
    }

    if (_recordingPhase == _RecordingPhase.recording) {
      final error = Theme.of(context).colorScheme.error;
      return _composerShell(
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.sm + 2),
            Icon(Icons.fiber_manual_record, color: error, size: 16),
            const SizedBox(width: AppSpacing.sm),
            const VoiceWaveform(active: true, barCount: 9, height: 24, barWidth: 3, gap: 3, color: AppTheme.coral),
            const SizedBox(width: AppSpacing.sm + 2),
            const Expanded(
              child: Text(
                'Recording... (sends automatically at 60s)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.stop_circle_rounded, color: error, size: 34),
              onPressed: _stopAndSendRecording,
            ),
          ],
        ),
      );
    }

    return _composerShell(
      child: Row(
        children: [
          IconButton(
            tooltip: 'Record a voice message',
            icon: const Icon(Icons.mic_rounded),
            onPressed: state.isSending ? null : _startRecording,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(46),
              backgroundColor: AppTheme.surface3,
              foregroundColor: AppTheme.coralLight,
              disabledBackgroundColor: AppTheme.surface2,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !state.isSending,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: 'Message',
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _SendButton(isSending: state.isSending, onPressed: state.isSending ? null : _sendText),
        ],
      ),
    );
  }
}

/// Bloom-gradient round send button with the spinner swapped in while a
/// send is in flight.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.isSending, required this.onPressed});

  final bool isSending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Send',
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: brandGradient(),
          boxShadow: [
            BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: -4),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(
              child: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// Initial-in-a-gradient-disc beside the name in the app bar.
class _TitleAvatar extends StatelessWidget {
  const _TitleAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: brandGradient(), shape: BoxShape.circle),
      child: Text(
        initial,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: Colors.white,
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
    final foreground = isMine ? Colors.white : AppTheme.textPrimary;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.lg - 2),
      topRight: const Radius.circular(AppRadius.lg - 2),
      bottomLeft: Radius.circular(isMine ? AppRadius.lg - 2 : AppRadius.xs),
      bottomRight: Radius.circular(isMine ? AppRadius.xs : AppRadius.lg - 2),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          gradient: isMine ? brandGradient() : null,
          color: isMine ? null : AppTheme.surface2,
          borderRadius: radius,
          border: isMine ? null : Border.all(color: AppTheme.stroke),
          boxShadow: isMine
              ? [
                  BoxShadow(
                    color: AppTheme.magenta.withValues(alpha: 0.28),
                    blurRadius: 16,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: message.type == MessageType.voice && message.audioUrl != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VoiceClipPlayer(
                    source: audioSourceFor(message.audioUrl!),
                    iconSize: 22,
                    tint: isMine ? Colors.white : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${message.audioDurationSec ?? 0}s',
                    style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                  ),
                  if (isMine) _StatusIcon(message: message),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      message.textContent ?? '',
                      style: TextStyle(color: foreground, height: 1.35, fontSize: 15),
                    ),
                  ),
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
    // Sits on the Bloom gradient: read = solid white, otherwise faded.
    final color = message.readAt != null ? Colors.white : Colors.white.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
