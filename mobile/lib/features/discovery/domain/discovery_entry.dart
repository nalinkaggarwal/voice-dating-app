enum DiscoveryDecision { pass, interested }

extension DiscoveryDecisionWire on DiscoveryDecision {
  /// Mirrors the backend's DecisionType enum values exactly.
  String get wireValue => switch (this) {
        DiscoveryDecision.pass => 'PASS',
        DiscoveryDecision.interested => 'INTERESTED',
      };
}

class DiscoveryEntry {
  const DiscoveryEntry({
    required this.id,
    required this.reasonText,
    this.voiceClipUrl,
  });

  factory DiscoveryEntry.fromJson(Map<String, dynamic> json) {
    return DiscoveryEntry(
      id: json['id'] as String,
      reasonText: json['reasonText'] as String,
      voiceClipUrl: json['voiceClipUrl'] as String?,
    );
  }

  final String id;
  final String reasonText;
  /// Signed, time-limited GET URL -- null if no approved voice recording.
  ///
  /// Deliberately the ONLY candidate-identifying field this model has.
  /// "Hear before you see" is the app's entire premise (see README) --
  /// the backend's today() response never includes a name or photo, so
  /// there is nothing here to accidentally render even by mistake.
  final String? voiceClipUrl;
}

class DiscoveryDecisionResult {
  const DiscoveryDecisionResult({required this.matched});

  factory DiscoveryDecisionResult.fromJson(Map<String, dynamic> json) {
    return DiscoveryDecisionResult(matched: json['matched'] as bool? ?? false);
  }

  final bool matched;
}
