import '../../../shared/api/api_client.dart';
import '../domain/live_snap_models.dart';

class LiveSnapRepository {
  LiveSnapRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<LiveSnapStartResult> startSession(String connectionId) async {
    final response = await _api.post('/live-snap/$connectionId/start', authenticated: true);
    return LiveSnapStartResult.fromJson(response);
  }

  /// Returns true only on the call that actually flips the Connection to
  /// AUTHENTICATED_MATCH (mirrors DiscoveryDecisionResult.matched's
  /// contract -- see connections.service.ts's markSnapDone).
  Future<bool> confirm(String connectionId) async {
    final response = await _api.post('/connections/$connectionId/snap/confirm', authenticated: true);
    return response['matched'] as bool? ?? false;
  }

  Future<void> decline(String connectionId) {
    return _api.post('/connections/$connectionId/decline', authenticated: true);
  }
}
