import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/error/app_exception.dart';
import 'package:lolly/features/messaging/application/message_thread_state.dart';
import 'package:lolly/features/messaging/data/chat_socket_client.dart';
import 'package:lolly/features/messaging/data/messaging_repository.dart';
import 'package:lolly/features/messaging/domain/message.dart';

// The real ChatSocketClient touches socket_io_client + flutter_secure_storage
// (TokenStorage) -- this fake replaces it entirely so tests never attempt a
// real connection, same reasoning as every other fake-over-real-plugin in
// this test suite (LiveSnapState, SignalingClient).
class _FakeSocketClient extends ChatSocketClient {
  void Function(Map<String, dynamic>)? _onNewMessage;
  void Function(Map<String, dynamic>)? _onDelivered;
  void Function(Map<String, dynamic>)? _onRead;
  void Function()? _onConnect;
  bool connected = false;
  bool disposed = false;

  @override
  Future<void> connect() async => connected = true;

  @override
  void onNewMessage(void Function(Map<String, dynamic> payload) callback) => _onNewMessage = callback;

  @override
  void onDelivered(void Function(Map<String, dynamic> payload) callback) => _onDelivered = callback;

  @override
  void onRead(void Function(Map<String, dynamic> payload) callback) => _onRead = callback;

  @override
  void onConnect(void Function() callback) => _onConnect = callback;

  @override
  void dispose() => disposed = true;

  void simulateConnect() => _onConnect?.call();
  void simulateNewMessage(Map<String, dynamic> payload) => _onNewMessage?.call(payload);
  void simulateDelivered(Map<String, dynamic> payload) => _onDelivered?.call(payload);
  void simulateRead(Map<String, dynamic> payload) => _onRead?.call(payload);
}

class _FakeRepository extends MessagingRepository {
  _FakeRepository({this.historyByQuery = const {}, this.sendTextError});

  /// Keyed by a simple description ('initial', 'since', 'before') so
  /// different calls in the same test can return different pages.
  final Map<String, MessageHistoryPage> historyByQuery;
  final Object? sendTextError;
  int markReadCalls = 0;
  final List<String> sentTexts = [];
  Message? nextSendResult;

  @override
  Future<MessageHistoryPage> getHistory(String connectionId, {String? before, String? since}) async {
    if (since != null) return historyByQuery['since'] ?? const MessageHistoryPage(messages: [], hasMore: false);
    if (before != null) return historyByQuery['before'] ?? const MessageHistoryPage(messages: [], hasMore: false);
    return historyByQuery['initial'] ?? const MessageHistoryPage(messages: [], hasMore: false);
  }

  @override
  Future<Message> sendText(String connectionId, String textContent) async {
    if (sendTextError != null) throw sendTextError!;
    sentTexts.add(textContent);
    return nextSendResult ??
        Message(
          id: 'sent-${sentTexts.length}',
          connectionId: connectionId,
          senderId: 'me',
          type: MessageType.text,
          textContent: textContent,
          sentAt: DateTime.now(),
        );
  }

  @override
  Future<Message> sendVoice(String connectionId, {required String audioUrl, required int audioDurationSec}) async {
    return Message(
      id: 'voice-1',
      connectionId: connectionId,
      senderId: 'me',
      type: MessageType.voice,
      audioUrl: audioUrl,
      audioDurationSec: audioDurationSec,
      sentAt: DateTime.now(),
    );
  }

  @override
  Future<({String uploadUrl, String key})> requestVoiceUploadUrl(String contentType) async {
    return (uploadUrl: 'https://s3.example.com/put', key: 'message-voice/abc.m4a');
  }

  @override
  Future<void> uploadToSignedUrl(String uploadUrl, Uint8List bytes, String contentType) async {}

  @override
  Future<void> markDelivered(String connectionId) async {}

  @override
  Future<void> markRead(String connectionId) async {
    markReadCalls++;
  }
}

Message _makeMessage({
  String id = 'msg-1',
  String senderId = 'them',
  DateTime? sentAt,
  DateTime? deliveredAt,
  DateTime? readAt,
}) {
  return Message(
    id: id,
    connectionId: 'conn-1',
    senderId: senderId,
    type: MessageType.text,
    textContent: 'hi',
    sentAt: sentAt ?? DateTime(2026, 10, 1, 10),
    deliveredAt: deliveredAt,
    readAt: readAt,
  );
}

void main() {
  group('MessageThreadState.load', () {
    test('populates messages from history and connects the socket', () async {
      final repository = _FakeRepository(
        historyByQuery: {
          'initial': MessageHistoryPage(messages: [_makeMessage()], hasMore: true),
        },
      );
      final socket = _FakeSocketClient();
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: repository,
        socket: socket,
      );

      await state.load();

      expect(state.messages, hasLength(1));
      expect(state.hasMoreHistory, isTrue);
      expect(state.isLoading, isFalse);
      expect(socket.connected, isTrue);
      expect(repository.markReadCalls, 1); // incoming messages marked seen on load
    });
  });

  group('MessageThreadState live delivery', () {
    test('appends an incoming message:new broadcast, deduped by id', () async {
      final socket = _FakeSocketClient();
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(),
        socket: socket,
      );
      await state.load();

      final incoming = _makeMessage(id: 'msg-new', sentAt: DateTime(2026, 10, 1, 11));
      socket.simulateNewMessage({
        'id': incoming.id,
        'connectionId': incoming.connectionId,
        'senderId': incoming.senderId,
        'type': 'TEXT',
        'textContent': incoming.textContent,
        'sentAt': incoming.sentAt.toIso8601String(),
      });
      // A duplicate delivery of the same message must not double-add it.
      socket.simulateNewMessage({
        'id': incoming.id,
        'connectionId': incoming.connectionId,
        'senderId': incoming.senderId,
        'type': 'TEXT',
        'textContent': incoming.textContent,
        'sentAt': incoming.sentAt.toIso8601String(),
      });

      expect(state.messages.where((m) => m.id == 'msg-new'), hasLength(1));
    });

    test('reconnect catch-up fetches messages newer than the last known one', () async {
      final existing = _makeMessage(id: 'msg-1', sentAt: DateTime(2026, 10, 1, 10));
      final missed = _makeMessage(id: 'msg-2', sentAt: DateTime(2026, 10, 1, 10, 5));
      final repository = _FakeRepository(
        historyByQuery: {
          'initial': MessageHistoryPage(messages: [existing], hasMore: false),
          'since': MessageHistoryPage(messages: [missed], hasMore: false),
        },
      );
      final socket = _FakeSocketClient();
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: repository,
        socket: socket,
      );
      await state.load();

      socket.simulateConnect(); // e.g. a reconnect after a drop
      await Future<void>.delayed(Duration.zero);

      expect(state.messages.map((m) => m.id), containsAll(['msg-1', 'msg-2']));
    });

    test('applies a delivered broadcast to my own messages up to the given time', () async {
      final mine = _makeMessage(id: 'msg-1', senderId: 'me', sentAt: DateTime(2026, 10, 1, 10));
      final socket = _FakeSocketClient();
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(historyByQuery: {'initial': MessageHistoryPage(messages: [mine], hasMore: false)}),
        socket: socket,
      );
      await state.load();
      expect(state.messages.single.deliveredAt, isNull);

      socket.simulateDelivered({'connectionId': 'conn-1', 'upTo': DateTime(2026, 10, 1, 10, 1).toIso8601String()});

      expect(state.messages.single.deliveredAt, isNotNull);
      expect(state.messages.single.readAt, isNull);
    });

    test('a read broadcast implies delivered too', () async {
      final mine = _makeMessage(id: 'msg-1', senderId: 'me', sentAt: DateTime(2026, 10, 1, 10));
      final socket = _FakeSocketClient();
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(historyByQuery: {'initial': MessageHistoryPage(messages: [mine], hasMore: false)}),
        socket: socket,
      );
      await state.load();

      socket.simulateRead({'connectionId': 'conn-1', 'upTo': DateTime(2026, 10, 1, 10, 1).toIso8601String()});

      expect(state.messages.single.deliveredAt, isNotNull);
      expect(state.messages.single.readAt, isNotNull);
    });

    test('a status broadcast never applies to the OTHER party\'s messages', () async {
      final theirs = _makeMessage(id: 'msg-1', senderId: 'them', sentAt: DateTime(2026, 10, 1, 10));
      final socket = _FakeSocketClient();
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(historyByQuery: {'initial': MessageHistoryPage(messages: [theirs], hasMore: false)}),
        socket: socket,
      );
      await state.load();

      socket.simulateRead({'connectionId': 'conn-1', 'upTo': DateTime(2026, 10, 1, 10, 1).toIso8601String()});

      expect(state.messages.single.readAt, isNull);
    });
  });

  group('MessageThreadState.sendText', () {
    test('appends the server-confirmed message on success', () async {
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(),
        socket: _FakeSocketClient(),
      );
      await state.load();

      final result = await state.sendText('hello');

      expect(result, isTrue);
      expect(state.messages.single.textContent, 'hello');
      expect(state.isSending, isFalse);
    });

    test('does nothing for blank text', () async {
      final repository = _FakeRepository();
      final state = MessageThreadState(connectionId: 'conn-1', currentUserId: 'me', repository: repository, socket: _FakeSocketClient());
      await state.load();

      final result = await state.sendText('   ');

      expect(result, isFalse);
      expect(repository.sentTexts, isEmpty);
    });

    test('surfaces the error message on failure', () async {
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(sendTextError: const AppException('Cannot message while connection status is CLOSED')),
        socket: _FakeSocketClient(),
      );
      await state.load();

      final result = await state.sendText('hello');

      expect(result, isFalse);
      expect(state.errorMessage, 'Cannot message while connection status is CLOSED');
    });
  });

  group('MessageThreadState.sendVoice', () {
    test('uploads then sends, appending the resulting message', () async {
      final state = MessageThreadState(
        connectionId: 'conn-1',
        currentUserId: 'me',
        repository: _FakeRepository(),
        socket: _FakeSocketClient(),
      );
      await state.load();

      final result = await state.sendVoice(Uint8List(0), contentType: 'audio/mp4', durationSec: 12);

      expect(result, isTrue);
      expect(state.messages.single.type, MessageType.voice);
      expect(state.messages.single.audioDurationSec, 12);
    });
  });

  group('MessageThreadState.loadOlder', () {
    test('prepends an older page and updates hasMoreHistory', () async {
      final newer = _makeMessage(id: 'msg-2', sentAt: DateTime(2026, 10, 1, 11));
      final older = _makeMessage(id: 'msg-1', sentAt: DateTime(2026, 10, 1, 9));
      final repository = _FakeRepository(
        historyByQuery: {
          'initial': MessageHistoryPage(messages: [newer], hasMore: true),
          'before': MessageHistoryPage(messages: [older], hasMore: false),
        },
      );
      final state = MessageThreadState(connectionId: 'conn-1', currentUserId: 'me', repository: repository, socket: _FakeSocketClient());
      await state.load();

      await state.loadOlder();

      expect(state.messages.map((m) => m.id), ['msg-1', 'msg-2']);
      expect(state.hasMoreHistory, isFalse);
    });

    test('is a no-op when there is no more history', () async {
      final state = MessageThreadState(connectionId: 'conn-1', currentUserId: 'me', repository: _FakeRepository(), socket: _FakeSocketClient());
      await state.load();

      await state.loadOlder(); // no messages at all, nothing to page from

      expect(state.messages, isEmpty);
    });
  });

  group('MessageThreadState.dispose', () {
    test('disposes the socket', () async {
      final socket = _FakeSocketClient();
      final state = MessageThreadState(connectionId: 'conn-1', currentUserId: 'me', repository: _FakeRepository(), socket: socket);
      await state.load();

      state.dispose();

      expect(socket.disposed, isTrue);
    });
  });
}
