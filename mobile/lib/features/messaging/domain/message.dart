enum MessageType { text, voice }

MessageType _typeFromWire(String raw) {
  const map = {'TEXT': MessageType.text, 'VOICE': MessageType.voice};
  return map[raw] ?? MessageType.text;
}

String messageTypeToWire(MessageType type) => switch (type) {
      MessageType.text => 'TEXT',
      MessageType.voice => 'VOICE',
    };

class Message {
  const Message({
    required this.id,
    required this.connectionId,
    required this.senderId,
    required this.type,
    required this.sentAt,
    this.textContent,
    this.audioUrl,
    this.audioDurationSec,
    this.deliveredAt,
    this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      connectionId: json['connectionId'] as String,
      senderId: json['senderId'] as String,
      type: _typeFromWire(json['type'] as String),
      textContent: json['textContent'] as String?,
      audioUrl: json['audioUrl'] as String?,
      audioDurationSec: json['audioDurationSec'] as int?,
      sentAt: DateTime.parse(json['sentAt'] as String),
      deliveredAt: json['deliveredAt'] != null ? DateTime.parse(json['deliveredAt'] as String) : null,
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt'] as String) : null,
    );
  }

  final String id;
  final String connectionId;
  final String senderId;
  final MessageType type;
  final String? textContent;
  /// Signed, time-limited GET URL -- same pattern as every other audio
  /// field in this app (VoiceAnswer.audioUrl, discovery's voiceClipUrl).
  final String? audioUrl;
  final int? audioDurationSec;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  bool isMine(String currentUserId) => senderId == currentUserId;

  /// Applies a delivered/read status broadcast locally -- see
  /// MessageThreadState, which uses this instead of re-fetching the whole
  /// message just to update two timestamp fields.
  Message withStatus({DateTime? deliveredAt, DateTime? readAt}) => Message(
        id: id,
        connectionId: connectionId,
        senderId: senderId,
        type: type,
        textContent: textContent,
        audioUrl: audioUrl,
        audioDurationSec: audioDurationSec,
        sentAt: sentAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        readAt: readAt ?? this.readAt,
      );
}
