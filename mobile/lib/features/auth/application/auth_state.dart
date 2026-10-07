import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/notifications/push_registrar.dart';
import '../data/auth_repository.dart';
import '../domain/auth_channel.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Single source of truth for auth state across the app -- app_router.dart
/// (or equivalent) listens to this to decide whether to show the
/// auth/onboarding flow or the main app shell.
///
/// WP7: also the one place that knows WHEN a device token should be
/// (un)registered -- every path that ends in `authenticated` syncs it,
/// logout unregisters it before the session is cleared. The how lives
/// behind [PushRegistrar]; with none passed (unit tests), nothing happens.
class AuthState extends ChangeNotifier {
  AuthState({AuthRepository? repository, PushRegistrar? pushRegistrar})
      : _repository = repository ?? AuthRepository(),
        _pushRegistrar = pushRegistrar;

  final AuthRepository _repository;
  final PushRegistrar? _pushRegistrar;

  AuthStatus status = AuthStatus.unknown;
  bool isLoading = false;
  String? errorMessage;
  String? _pendingChallengeId;

  Future<void> bootstrap() async {
    status = (await _repository.hasStoredSession())
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
    notifyListeners();
    if (status == AuthStatus.authenticated) _syncPush();
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
      _syncPush();
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
      _syncPush();
    });
  }

  Future<void> logout() async {
    // Needs the access token the repository is about to clear, so it goes
    // first. The registrar swallows its own errors: a failed unregister
    // must never keep someone logged in.
    await _pushRegistrar?.unregisterForSignOut();
    await _repository.logout();
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // Fire-and-forget on purpose: the permission prompt and token fetch
  // must not hold up the login UI, and the registrar never throws.
  void _syncPush() {
    final registrar = _pushRegistrar;
    if (registrar != null) unawaited(registrar.syncForSignedInUser());
  }
}
