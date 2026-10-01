import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/error/app_exception.dart';
import 'package:lolly/features/live_snap/application/live_snap_state.dart';
import 'package:lolly/features/live_snap/data/live_snap_repository.dart';

// start()/the WebRTC+signaling flow aren't covered here: they call into
// flutter_webrtc's native platform channel (RTCVideoRenderer.initialize,
// createPeerConnection, getUserMedia), which has no implementation in a
// plain `flutter test` run (no device/emulator). confirmMatch/declineMatch
// are the one part of this class that never touches WebRTC at all --
// pure repository calls -- so they're the part that's actually testable
// here. Covering the rest would need mocking flutter_webrtc's method
// channel directly, not a fake repository.
class _FakeRepository extends LiveSnapRepository {
  _FakeRepository({this.confirmResult = false, this.confirmError, this.declineError});

  final bool confirmResult;
  final Object? confirmError;
  final Object? declineError;

  bool declineCalled = false;

  @override
  Future<bool> confirm(String connectionId) async {
    if (confirmError != null) throw confirmError!;
    return confirmResult;
  }

  @override
  Future<void> decline(String connectionId) async {
    declineCalled = true;
    if (declineError != null) throw declineError!;
  }
}

void main() {
  group('LiveSnapState.confirmMatch', () {
    test('returns the repository result on success', () async {
      final state = LiveSnapState(
        connectionId: 'conn-1',
        repository: _FakeRepository(confirmResult: true),
      );

      expect(await state.confirmMatch(), isTrue);
      expect(state.errorMessage, isNull);
    });

    test('returns false and surfaces the error message on failure', () async {
      final state = LiveSnapState(
        connectionId: 'conn-1',
        repository: _FakeRepository(confirmError: const AppException('Network error')),
      );

      expect(await state.confirmMatch(), isFalse);
      expect(state.errorMessage, 'Network error');
    });
  });

  group('LiveSnapState.declineMatch', () {
    test('returns true and calls the repository on success', () async {
      final repository = _FakeRepository();
      final state = LiveSnapState(connectionId: 'conn-1', repository: repository);

      expect(await state.declineMatch(), isTrue);
      expect(repository.declineCalled, isTrue);
    });

    test('returns false and surfaces the error message on failure', () async {
      final state = LiveSnapState(
        connectionId: 'conn-1',
        repository: _FakeRepository(declineError: const AppException('Already closed')),
      );

      expect(await state.declineMatch(), isFalse);
      expect(state.errorMessage, 'Already closed');
    });
  });
}
