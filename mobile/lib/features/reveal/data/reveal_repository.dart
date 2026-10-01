import '../../../shared/api/api_client.dart';
import '../domain/reveal_profile.dart';

class RevealRepository {
  RevealRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<RevealProfile> getReveal(String connectionId) async {
    final response = await _api.get('/connections/$connectionId/reveal', authenticated: true);
    return RevealProfile.fromJson(response);
  }

  Future<void> decline(String connectionId) {
    return _api.post('/connections/$connectionId/decline', authenticated: true);
  }
}
