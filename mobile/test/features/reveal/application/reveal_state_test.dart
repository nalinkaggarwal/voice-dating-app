import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/core/error/app_exception.dart';
import 'package:lolly/features/reveal/application/reveal_state.dart';
import 'package:lolly/features/reveal/data/reveal_repository.dart';
import 'package:lolly/features/reveal/domain/reveal_profile.dart';

class _FakeRepository extends RevealRepository {
  _FakeRepository({this.profile, this.getRevealError, this.declineError});

  final RevealProfile? profile;
  final Object? getRevealError;
  final Object? declineError;

  bool declineCalled = false;

  @override
  Future<RevealProfile> getReveal(String connectionId) async {
    if (getRevealError != null) throw getRevealError!;
    return profile!;
  }

  @override
  Future<void> decline(String connectionId) async {
    declineCalled = true;
    if (declineError != null) throw declineError!;
  }
}

void main() {
  group('RevealState.load', () {
    test('populates profile on success', () async {
      const profile = RevealProfile(userId: 'user-b', displayName: 'Jordan', photoUrl: 'https://example.com/jordan.jpg');
      final state = RevealState(repository: _FakeRepository(profile: profile));

      await state.load('conn-1');

      expect(state.isLoading, isFalse);
      expect(state.profile, same(profile));
      expect(state.errorMessage, isNull);
    });

    test('surfaces the error message and leaves profile null on failure', () async {
      final state = RevealState(
        repository: _FakeRepository(getRevealError: const AppException('Not matched yet')),
      );

      await state.load('conn-1');

      expect(state.isLoading, isFalse);
      expect(state.profile, isNull);
      expect(state.errorMessage, 'Not matched yet');
    });
  });

  group('RevealState.decline', () {
    test('returns true and calls the repository on success', () async {
      final repository = _FakeRepository();
      final state = RevealState(repository: repository);

      final result = await state.decline('conn-1');

      expect(result, isTrue);
      expect(repository.declineCalled, isTrue);
      expect(state.errorMessage, isNull);
    });

    test('returns false and surfaces the error message on failure', () async {
      final state = RevealState(
        repository: _FakeRepository(declineError: const AppException('Network error')),
      );

      final result = await state.decline('conn-1');

      expect(result, isFalse);
      expect(state.errorMessage, 'Network error');
    });
  });
}
