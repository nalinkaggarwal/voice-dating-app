/// The data half of every push the backend sends (see
/// backend/src/modules/notifications/notifications.service.ts, `PushKind`).
/// Pure Dart on purpose: no Flutter, no Firebase, so the parsing and
/// routing rules are unit-testable without a device.
enum PushKind { newMessage, mutualMatch, liveSnapInvite, authenticatedMatch }

/// Where a tap on the notification should land.
enum PushDestination {
  /// Open the conversation (`MessageThreadScreen`).
  messageThread,

  /// Open the Live Snap call screen for the connection.
  liveSnapCall,

  /// Just bring the app to the front. Used for the anonymous mutual-match
  /// push: identity isn't revealed yet, so there's no specific screen to
  /// deep-link into -- Discovery/Matches already show the new match.
  home,
}

class PushPayload {
  const PushPayload({
    required this.kind,
    required this.connectionId,
    required this.otherUserId,
    this.otherDisplayName,
  });

  final PushKind kind;
  final String connectionId;
  final String otherUserId;

  /// Absent on MUTUAL_MATCH by design ("hear before you see") and when
  /// the sender simply has no display name.
  final String? otherDisplayName;

  /// Parses FCM's flat string->string data map. Returns null for anything
  /// this client version doesn't understand -- an unknown `type` from a
  /// newer backend, or a payload missing its ids, must degrade to "just
  /// open the app", never crash the tap handler.
  static PushPayload? fromData(Map<String, dynamic> data) {
    final kind = _kindFromWire(data['type']?.toString());
    if (kind == null) return null;

    final connectionId = data['connectionId']?.toString();
    final otherUserId = data['otherUserId']?.toString();
    if (connectionId == null || connectionId.isEmpty || otherUserId == null || otherUserId.isEmpty) {
      return null;
    }

    final name = data['otherDisplayName']?.toString();
    return PushPayload(
      kind: kind,
      connectionId: connectionId,
      otherUserId: otherUserId,
      otherDisplayName: (name == null || name.isEmpty) ? null : name,
    );
  }

  static PushKind? _kindFromWire(String? value) {
    switch (value) {
      case 'NEW_MESSAGE':
        return PushKind.newMessage;
      case 'MUTUAL_MATCH':
        return PushKind.mutualMatch;
      case 'LIVE_SNAP_INVITE':
        return PushKind.liveSnapInvite;
      case 'AUTHENTICATED_MATCH':
        return PushKind.authenticatedMatch;
      default:
        return null;
    }
  }

  PushDestination get destination {
    switch (kind) {
      case PushKind.newMessage:
      case PushKind.authenticatedMatch:
        return PushDestination.messageThread;
      case PushKind.liveSnapInvite:
        return PushDestination.liveSnapCall;
      case PushKind.mutualMatch:
        return PushDestination.home;
    }
  }

  /// Whether a push arriving while the app is in the FOREGROUND should be
  /// surfaced as a visible notification. Only one case is redundant: a new
  /// message for the thread the user is currently looking at -- the socket
  /// already rendered it. Everything else (a message in another thread, a
  /// match, an incoming Live Snap) is shown.
  bool shouldShowInForeground({String? activeConnectionId}) {
    return !(kind == PushKind.newMessage && activeConnectionId == connectionId);
  }
}
