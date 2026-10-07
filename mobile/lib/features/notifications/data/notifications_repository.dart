import '../../../shared/api/api_client.dart';

/// Device-token registration against the WP7 notifications endpoints.
/// Nothing here receives or displays a push -- that's
/// core/notifications/push_notifications.dart.
class NotificationsRepository {
  NotificationsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// [platform] is the backend's DevicePlatform enum: 'ANDROID' | 'IOS'.
  Future<void> registerDevice({required String token, required String platform}) async {
    await _api.post(
      '/notifications/devices',
      body: {'token': token, 'platform': platform},
      authenticated: true,
    );
  }

  Future<void> unregisterDevice({required String token}) async {
    await _api.post(
      '/notifications/devices/unregister',
      body: {'token': token},
      authenticated: true,
    );
  }
}
