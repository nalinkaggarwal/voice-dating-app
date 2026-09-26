import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../data/auth_repository.dart';
import '../domain/auth_channel.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Single source of truth for auth state across the app -- app_router.dart
/// (or equivalent) listens to this to decide whether to show the
/// auth/onboarding flow or the main app shell.
class AuthState extends ChangeNotifier {
  AuthState({AuthRepository? repository}) : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

  AuthStatus status = AuthStatus.unknown;
  bool isLoading = false;
  String? errorMessage;
  String? _pendingChallengeId;

  Future<void> bootstrap() async {
    status = (await _repository.hasStoredSession())
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AppException catch (e) {
      errorMessage = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> startSignup({
    required AuthChannel channel,
    required String identifier,
    required DateTime dateOfBirth,
  }) {
    return _run(() async {
      _pendingChallengeId = await _repository.startSignup(
        channel: channel,
        identifier: identifier,
        dateOfBirth: dateOfBirth,
      );
    });
  }

  Future<bool> verifySignup(String code) {
    return _run(() async {
      final challengeId = _pendingChallengeId;
      if (challengeId == null) {
        throw const AppException('No signup in progress');
      }
      await _repository.verifySignup(challengeId: challengeId, code: code);
      status = AuthStatus.authenticated;
    });
  }

  Future<bool> startLogin({required AuthChannel channel, required String identifier}) {
    return _run(() async {
      _pendingChallengeId = await _repository.startLogin(channel: channel, identifier: identifier);
    });
  }

  Future<bool> verifyLogin(String code) {
    return _run(() async {
      final challengeId = _pendingChallengeId;
      if (challengeId == null) {
        throw const AppException('No login in progress');
      }
      await _repository.verifyLogin(challengeId: challengeId, code: code);
      status = AuthStatus.authenticated;
    });
  }

  Future<void> logout() async {
    await _repository.logout();
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
