import '../../../shared/api/api_client.dart';
import '../domain/discovery_entry.dart';

class DiscoveryRepository {
  DiscoveryRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<DiscoveryEntry>> getToday() async {
    final response = await _api.get('/discovery/queue/today', authenticated: true);
    final rawEntries = response['entries'] as List<dynamic>? ?? [];
    return rawEntries
        .map((e) => DiscoveryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DiscoveryDecisionResult> decide(String entryId, DiscoveryDecision decision) async {
    final response = await _api.post(
      '/discovery/queue/$entryId/decide',
      authenticated: true,
      body: {'decision': decision.wireValue},
    );
    return DiscoveryDecisionResult.fromJson(response);
  }
}
