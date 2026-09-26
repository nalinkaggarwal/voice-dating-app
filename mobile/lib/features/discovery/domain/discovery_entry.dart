enum DiscoveryDecision { pass, interested }

extension DiscoveryDecisionWire on DiscoveryDecision {
  /// Mirrors the backend's DecisionType enum values exactly.
  String get wireValue => switch (this) {
        DiscoveryDecision.pass => 'PASS',
        DiscoveryDecision.interested => 'INTERESTED',
      };
}

class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.userId,
    this.displayName,
    this.photoUrl,
    this.voiceClipUrl,
  });

  factory DiscoveryCandidate.fromJson(Map<String, dynamic> json) {
    return DiscoveryCandidate(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      voiceClipUrl: json['voiceClipUrl'] as String?,
    );
  }

  final String userId;
  final String? displayName;
  /// Signed, time-limited GET URL -- null if no photo uploaded yet.
  final String? photoUrl;
  /// Signed, time-limited GET URL -- null if no approved voice recording.
  final String? voiceClipUrl;
}

class DiscoveryEntry {
  const DiscoveryEntry({
    required this.id,
    required this.reasonText,
    required this.candidate,
  });

  factory DiscoveryEntry.fromJson(Map<String, dynamic> json) {
    return DiscoveryEntry(
      id: json['id'] as String,
      reasonText: json['reasonText'] as String,
      candidate: DiscoveryCandidate.fromJson(json['candidate'] as Map<String, dynamic>),
    );
  }

  final String id;
  final String reasonText;
  final DiscoveryCandidate candidate;
}

class DiscoveryDecisionResult {
  const DiscoveryDecisionResult({required this.matched});

  factory DiscoveryDecisionResult.fromJson(Map<String, dynamic> json) {
    return DiscoveryDecisionResult(matched: json['matched'] as bool? ?? false);
  }

  final bool matched;
}
