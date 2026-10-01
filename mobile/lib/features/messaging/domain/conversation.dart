import 'message.dart';

class LastMessagePreview {
  const LastMessagePreview({required this.type, required this.sentAt, this.textContent});

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) {
    return LastMessagePreview(
      type: json['type'] == 'VOICE' ? MessageType.voice : MessageType.text,
      textContent: json['textContent'] as String?,
      sentAt: DateTime.parse(json['sentAt'] as String),
    );
  }

  final MessageType type;
  final String? textContent;
  final DateTime sentAt;
}

/// One row in the conversation list -- one per AUTHENTICATED_MATCH/ACTIVE
/// Connection this user is part of. WP3's one-candidate-a-day limit caps
/// how fast NEW matches appear, not how many stay active at once, so
/// there can legitimately be more than one of these.
class Conversation {
  const Conversation({
    required this.connectionId,
    required this.displayName,
    required this.photoUrl,
    required this.lastMessage,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final rawLastMessage = json['lastMessage'] as Map<String, dynamic>?;
    return Conversation(
      connectionId: json['connectionId'] as String,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      lastMessage: rawLastMessage != null ? LastMessagePreview.fromJson(rawLastMessage) : null,
    );
  }

  final String connectionId;
  final String? displayName;
  final String? photoUrl;
  final LastMessagePreview? lastMessage;
}
