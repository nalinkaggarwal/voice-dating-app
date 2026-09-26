import '../../../shared/api/api_client.dart';
import '../../../shared/api/token_storage.dart';
import '../domain/auth_channel.dart';

/// All calls to the backend's /auth/* endpoints. Presentation code never
/// touches ApiClient directly -- only this repository and AuthController.
class AuthRepository {
  AuthRepository({ApiClient? apiClient, TokenStorage? tokenStorage})
      : _api = apiClient ?? ApiClient(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  final ApiClient _api;
  final TokenStorage _tokenStorage;

  Future<String> startSignup({
    required AuthChannel channel,
    required String identifier,
    required DateTime dateOfBirth,
  }) async {
    final response = await _api.post(
      '/auth/signup/start',
      body: {
        'channel': channel.wireValue,
        'identifier': identifier,
        // Date-only, matches @IsDateString on the backend.
        'dateOfBirth': dateOfBirth.toIso8601String().split('T').first,
      },
    );
    return response['challengeId'] as String;
  }

  Future<void> verifySignup({required String challengeId, required String code}) async {
    final response = await _api.post(
      '/auth/signup/verify',
      body: {'challengeId': challengeId, 'code': code},
    );
    await _persistTokens(response);
  }

  Future<String> startLogin({required AuthChannel channel, required String identifier}) async {
    final response = await _api.post(
      '/auth/login/start',
      body: {'channel': channel.wireValue, 'identifier': identifier},
    );
    return response['challengeId'] as String;
  }

  Future<void> verifyLogin({required String challengeId, required String code}) async {
    final response = await _api.post(
      '/auth/login/verify',
      body: {'challengeId': challengeId, 'code': code},
    );
    await _persistTokens(response);
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken != null) {
      // Best-effort -- the local session is cleared regardless of whether
      // the server call succeeds (e.g. offline logout must still work).
      try {
        await _api.post('/auth/logout', body: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await _tokenStorage.clear();
  }

  Future<bool> hasStoredSession() async {
    return (await _tokenStorage.readRefreshToken()) != null;
  }

  Future<void> _persistTokens(Map<String, dynamic> response) async {
    final tokens = response['tokens'] as Map<String, dynamic>;
    await _tokenStorage.saveTokens(
      accessToken: tokens['accessToken'] as String,
      refreshToken: tokens['refreshToken'] as String,
    );
  }
}
