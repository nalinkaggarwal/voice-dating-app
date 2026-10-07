import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/notifications/push_payload.dart';

void main() {
  group('PushPayload.fromData', () {
    test('parses every backend PushKind wire value', () {
      const wire = {
        'NEW_MESSAGE': PushKind.newMessage,
        'MUTUAL_MATCH': PushKind.mutualMatch,
        'LIVE_SNAP_INVITE': PushKind.liveSnapInvite,
        'AUTHENTICATED_MATCH': PushKind.authenticatedMatch,
      };
      for (final entry in wire.entries) {
        final payload = PushPayload.fromData({'type': entry.key, 'connectionId': 'c1', 'otherUserId': 'u2'});
        expect(payload, isNotNull, reason: entry.key);
        expect(payload!.kind, entry.value, reason: entry.key);
        expect(payload.connectionId, 'c1');
        expect(payload.otherUserId, 'u2');
      }
    });

    test('returns null for an unknown type rather than throwing (forward compatibility)', () {
      expect(PushPayload.fromData({'type': 'SOMETHING_NEW', 'connectionId': 'c1', 'otherUserId': 'u2'}), isNull);
      expect(PushPayload.fromData({}), isNull);
    });

    test('returns null when either id is missing or empty', () {
      expect(PushPayload.fromData({'type': 'NEW_MESSAGE', 'otherUserId': 'u2'}), isNull);
      expect(PushPayload.fromData({'type': 'NEW_MESSAGE', 'connectionId': '', 'otherUserId': 'u2'}), isNull);
      expect(PushPayload.fromData({'type': 'NEW_MESSAGE', 'connectionId': 'c1'}), isNull);
    });

    test('treats an absent or empty display name as null', () {
      expect(
        PushPayload.fromData({'type': 'MUTUAL_MATCH', 'connectionId': 'c1', 'otherUserId': 'u2'})!.otherDisplayName,
        isNull,
      );
      expect(
        PushPayload.fromData({
          'type': 'NEW_MESSAGE',
          'connectionId': 'c1',
          'otherUserId': 'u2',
          'otherDisplayName': '',
        })!
            .otherDisplayName,
        isNull,
      );
      expect(
        PushPayload.fromData({
          'type': 'NEW_MESSAGE',
          'connectionId': 'c1',
          'otherUserId': 'u2',
          'otherDisplayName': 'Asha',
        })!
            .otherDisplayName,
        'Asha',
      );
    });
  });

  group('PushPayload.destination', () {
    PushPayload of(PushKind kind) => PushPayload(kind: kind, connectionId: 'c1', otherUserId: 'u2');

    test('messages and authenticated matches open the thread', () {
      expect(of(PushKind.newMessage).destination, PushDestination.messageThread);
      expect(of(PushKind.authenticatedMatch).destination, PushDestination.messageThread);
    });

    test('a Live Snap invite opens the call', () {
      expect(of(PushKind.liveSnapInvite).destination, PushDestination.liveSnapCall);
    });

    test('an anonymous mutual match only brings the app to the front', () {
      expect(of(PushKind.mutualMatch).destination, PushDestination.home);
    });
  });

  group('PushPayload.shouldShowInForeground', () {
    test('suppresses only a new message for the thread currently on screen', () {
      const msg = PushPayload(kind: PushKind.newMessage, connectionId: 'c1', otherUserId: 'u2');
      expect(msg.shouldShowInForeground(activeConnectionId: 'c1'), isFalse);
      expect(msg.shouldShowInForeground(activeConnectionId: 'c2'), isTrue);
      expect(msg.shouldShowInForeground(activeConnectionId: null), isTrue);
    });

    test('never suppresses a Live Snap invite or a match, even for the open thread', () {
      for (final kind in [PushKind.liveSnapInvite, PushKind.mutualMatch, PushKind.authenticatedMatch]) {
        final payload = PushPayload(kind: kind, connectionId: 'c1', otherUserId: 'u2');
        expect(payload.shouldShowInForeground(activeConnectionId: 'c1'), isTrue, reason: '$kind');
      }
    });
  });
}
