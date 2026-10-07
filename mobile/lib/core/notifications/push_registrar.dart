/// The only thing AuthState knows about push notifications. Kept as a
/// plain interface (no Firebase import) so AuthState stays unit-testable
/// with a fake, the same way it already takes an AuthRepository.
abstract class PushRegistrar {
  /// After a successful login/signup, and on app start with a stored
  /// session: obtain the device token and register it with the backend.
  /// Must never throw -- push being unavailable is not a login failure.
  Future<void> syncForSignedInUser();

  /// Before the session is cleared on logout (the call needs the access
  /// token): tell the backend to forget this device, so the next account
  /// to log in on this phone -- or nobody -- gets the pushes.
  Future<void> unregisterForSignOut();
}
