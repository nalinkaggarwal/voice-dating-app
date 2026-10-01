import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../data/chat_socket_client.dart';
import '../data/messaging_repository.dart';
import '../domain/message.dart';

/// Owns one open conversation: history/pagination, sending (text and
/// voice), and live delivery while this thread is open. There is NO push
/// notification infra in this project (see README) -- live delivery only
/// works while this screen (or another with a socket connected) is open
/// on both ends. Message persistence is correct regardless: `load()`
/// always starts from the real REST history, and `since`-based catch-up
/// on every (re)connect closes any gap a dropped socket leaves, same
/// "ask for the truth, don't trust what you think you already have"
/// reasoning as OnboardingState.resumeFrom.
class MessageThreadState extends ChangeNotifier {
  MessageThreadState({
    required this.connectionId,
    required this.currentUserId,
    MessagingRepository? repository,
    ChatSocketClient? socket,
  })  : _repository = repository ?? MessagingRepository(),
        _socket = socket ?? ChatSocketClient();

  final String connectionId;
  final String currentUserId;
  final MessagingRepository _repository;
  final ChatSocketClient _socket;

  bool isLoading = true;
  bool isSending = false;
  String? errorMessage;
  List<Message> messages = [];
  bool hasMoreHistory = true;
  bool _disposed = false;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _repository.getHistory(connectionId);
      messages = page.messages;
      hasMoreHistory = page.hasMore;
      await _connectSocket();
      await _markIncomingSeen();
    } on AppException catch (e) {
      errorMessage = e.message;
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<void> _connectSocket() async {
    await _socket.connect();
    _socket.onNewMessage(_handleIncomingMessage);
    _socket.onDelivered((payload) => _applyStatusBroadcast(payload, delivered: true));
    _socket.onRead((payload) => _applyStatusBroadcast(payload, delivered: false));
    _socket.onConnect(() => unawaited(_catchUp()));
  }

  /// Runs on every socket connect, including the very first one and any
  /// reconnect after a drop -- the same handler covers both.
  Future<void> _catchUp() async {
    final lastKnown = messages.isEmpty ? null : messages.last.sentAt;
    try {
      final page = await _repository.getHistory(connectionId, since: lastKnown?.toIso8601String());
      for (final message in page.messages) {
        _appendIfNew(message);
      }
      await _markIncomingSeen();
    } catch (_) {
      // Best-effort -- the next connect (or a manual pull-to-refresh, if
      // the UI adds one) tries again. Not surfacing an error here since a
      // momentary catch-up miss isn't the kind of thing worth interrupting
      // the user over; load()'s own errorMessage covers a hard failure.
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> payload) {
    _appendIfNew(Message.fromJson(payload));
    unawaited(_markIncomingSeen());
  }

  void _appendIfNew(Message message) {
    if (messages.any((m) => m.id == message.id)) return;
    messages = [...messages, message]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    _notify();
  }

  void _applyStatusBroadcast(Map<String, dynamic> payload, {required bool delivered}) {
    final upTo = DateTime.parse(payload['upTo'] as String);
    messages = messages.map((m) {
      if (!m.isMine(currentUserId) || m.sentAt.isAfter(upTo)) return m;
      return delivered ? m.withStatus(deliveredAt: upTo) : m.withStatus(deliveredAt: upTo, readAt: upTo);
    }).toList();
    _notify();
  }

  /// Marks whatever the OTHER party has sent as read (which implies
  /// delivered too -- see MessagingService.markRead) now that this
  /// thread is open and visible. Best-effort: a failure here just means
  /// the sender's read receipt is delayed, not that anything is lost.
  Future<void> _markIncomingSeen() async {
    try {
      await _repository.markRead(connectionId);
    } catch (_) {
      // best-effort, see above
    }
  }

  Future<void> loadOlder() async {
    if (!hasMoreHistory || messages.isEmpty) return;
    try {
      final page = await _repository.getHistory(connectionId, before: messages.first.sentAt.toIso8601String());
      messages = [...page.messages, ...messages];
      hasMoreHistory = page.hasMore;
      _notify();
    } on AppException catch (e) {
      errorMessage = e.message;
      _notify();
    }
  }

  Future<bool> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return _runSend(() => _repository.sendText(connectionId, trimmed));
  }

  Future<bool> sendVoice(Uint8List bytes, {required String contentType, required int durationSec}) {
    return _runSend(() async {
      final target = await _repository.requestVoiceUploadUrl(contentType);
      await _repository.uploadToSignedUrl(target.uploadUrl, bytes, contentType);
      return _repository.sendVoice(connectionId, audioUrl: target.key, audioDurationSec: durationSec);
    });
  }

  Future<bool> _runSend(Future<Message> Function() action) async {
    isSending = true;
    errorMessage = null;
    _notify();
    try {
      final message = await action();
      _appendIfNew(message);
      return true;
    } on AppException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isSending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _socket.dispose();
    super.dispose();
  }
}
