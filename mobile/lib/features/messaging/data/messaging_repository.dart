import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/error/app_exception.dart';
import '../../../shared/api/api_client.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';

class MessageHistoryPage {
  const MessageHistoryPage({required this.messages, required this.hasMore});

  factory MessageHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? [];
    return MessageHistoryPage(
      messages: rawMessages.map((m) => Message.fromJson(m as Map<String, dynamic>)).toList(),
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  final List<Message> messages;
  final bool hasMore;
}

class MessagingRepository {
  MessagingRepository({ApiClient? apiClient, http.Client? rawHttpClient})
      : _api = apiClient ?? ApiClient(),
        _rawHttp = rawHttpClient ?? http.Client();

  final ApiClient _api;
  // Same reasoning as OnboardingRepository's own copy of this: a signed
  // URL carries its own auth in the query string, and the body is raw
  // bytes, not JSON, so ApiClient's usual behavior doesn't apply.
  final http.Client _rawHttp;

  Future<List<Conversation>> listConversations() async {
    final response = await _api.get('/messaging/conversations', authenticated: true);
    final raw = response['conversations'] as List<dynamic>? ?? [];
    return raw.map((c) => Conversation.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<MessageHistoryPage> getHistory(String connectionId, {String? before, String? since}) async {
    final query = <String>[
      if (before != null) 'before=${Uri.encodeQueryComponent(before)}',
      if (since != null) 'since=${Uri.encodeQueryComponent(since)}',
    ].join('&');
    final path = '/messaging/$connectionId/messages${query.isNotEmpty ? '?$query' : ''}';
    final response = await _api.get(path, authenticated: true);
    return MessageHistoryPage.fromJson(response);
  }

  Future<Message> sendText(String connectionId, String textContent) async {
    final response = await _api.post(
      '/messaging/$connectionId/messages',
      authenticated: true,
      body: {'type': messageTypeToWire(MessageType.text), 'textContent': textContent},
    );
    return Message.fromJson(response);
  }

  Future<Message> sendVoice(String connectionId, {required String audioUrl, required int audioDurationSec}) async {
    final response = await _api.post(
      '/messaging/$connectionId/messages',
      authenticated: true,
      body: {
        'type': messageTypeToWire(MessageType.voice),
        'audioUrl': audioUrl,
        'audioDurationSec': audioDurationSec,
      },
    );
    return Message.fromJson(response);
  }

  Future<({String uploadUrl, String key})> requestVoiceUploadUrl(String contentType) async {
    final response = await _api.post(
      '/messaging/voice/upload-url',
      authenticated: true,
      body: {'contentType': contentType},
    );
    return (uploadUrl: response['uploadUrl'] as String, key: response['key'] as String);
  }

  Future<void> markDelivered(String connectionId) {
    return _api.post('/messaging/$connectionId/delivered', authenticated: true);
  }

  Future<void> markRead(String connectionId) {
    return _api.post('/messaging/$connectionId/read', authenticated: true);
  }

  Future<void> uploadToSignedUrl(String uploadUrl, Uint8List bytes, String contentType) async {
    final response = await _rawHttp.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('Voice message upload failed', statusCode: response.statusCode);
    }
  }
}
