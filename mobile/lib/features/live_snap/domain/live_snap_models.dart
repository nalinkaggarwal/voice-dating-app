/// Lifecycle of the call screen itself -- distinct from the backend's
/// LiveSnapSessionStatus (RINGING/ACTIVE/ENDED/MISSED), which tracks the
/// session row, not what this specific client is doing right now.
enum LiveSnapCallStatus {
  requestingPermission,
  permissionDenied,
  waiting,
  connecting,
  active,
  ended,
}

/// One STUN/TURN server entry, as flutter_webrtc's RTCConfiguration
/// expects it. STUN-only for this pass -- see live-snap.controller.ts.
class IceServerConfig {
  const IceServerConfig({required this.urls});

  factory IceServerConfig.fromJson(Map<String, dynamic> json) {
    return IceServerConfig(urls: json['urls'] as String);
  }

  final String urls;

  Map<String, dynamic> toMap() => {'urls': urls};
}

class LiveSnapStartResult {
  const LiveSnapStartResult({required this.sessionId, required this.iceServers});

  factory LiveSnapStartResult.fromJson(Map<String, dynamic> json) {
    final session = json['session'] as Map<String, dynamic>;
    final rawIceServers = json['iceServers'] as List<dynamic>? ?? [];
    return LiveSnapStartResult(
      sessionId: session['id'] as String,
      iceServers: rawIceServers.map((s) => IceServerConfig.fromJson(s as Map<String, dynamic>)).toList(),
    );
  }

  final String sessionId;
  final List<IceServerConfig> iceServers;
}
