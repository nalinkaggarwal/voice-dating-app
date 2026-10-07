import '../../../shared/api/api_client.dart';
import '../domain/report_reason.dart';

/// block()/report() -- see ConnectionsService.block and
/// ModerationService.report on the backend. Deliberately two independent
/// calls, never chained: reporting never blocks, blocking never requires
/// a report on file first (see schema.prisma's own comment on Report).
class TrustSafetyRepository {
  TrustSafetyRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<void> blockUser(String blockedUserId) {
    return _api.post(
      '/connections/block',
      authenticated: true,
      body: {'blockedUserId': blockedUserId},
    );
  }

  Future<void> reportUser({
    required String reportedUserId,
    required ReportReason reason,
    required ReportContext context,
    String? contextId,
    String? details,
  }) {
    return _api.post(
      '/moderation/reports',
      authenticated: true,
      body: {
        'reportedUserId': reportedUserId,
        'reason': reason.wireValue,
        'context': context.wireValue,
        if (contextId != null) 'contextId': contextId,
        if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
      },
    );
  }
}
