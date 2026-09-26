import 'profile_claim.dart';

enum VoiceAnswerStatus {
  uploaded,
  transcribing,
  transcribed,
  extracting,
  draftReady,
  userApproved,
  failed,
}

VoiceAnswerStatus _statusFromWire(String raw) {
  // Backend enum values are already SCREAMING_SNAKE with no multi-word
  // ambiguity issues here (unlike UserStatus's AI_REVIEW_DONE case) --
  // a direct map is clearer than the generic conversion helper for just
  // seven known values.
  const map = {
    'UPLOADED': VoiceAnswerStatus.uploaded,
    'TRANSCRIBING': VoiceAnswerStatus.transcribing,
    'TRANSCRIBED': VoiceAnswerStatus.transcribed,
    'EXTRACTING': VoiceAnswerStatus.extracting,
    'DRAFT_READY': VoiceAnswerStatus.draftReady,
    'USER_APPROVED': VoiceAnswerStatus.userApproved,
    'FAILED': VoiceAnswerStatus.failed,
  };
  return map[raw] ?? VoiceAnswerStatus.uploaded;
}

class VoiceAnswer {
  const VoiceAnswer({
    required this.id,
    required this.status,
    required this.claims,
    this.failureReason,
  });

  factory VoiceAnswer.fromJson(Map<String, dynamic> json) {
    final rawClaims = json['claims'] as List<dynamic>? ?? [];
    return VoiceAnswer(
      id: json['id'] as String,
      status: _statusFromWire(json['status'] as String),
      failureReason: json['failureReason'] as String?,
      claims: rawClaims
          .map((c) => ProfileClaim.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final VoiceAnswerStatus status;
  final String? failureReason;
  final List<ProfileClaim> claims;
}
