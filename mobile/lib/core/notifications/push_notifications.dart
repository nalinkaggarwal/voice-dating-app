import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/live_snap/presentation/live_snap_call_screen.dart';
import '../../features/messaging/presentation/message_thread_screen.dart';
import '../../features/notifications/data/notifications_repository.dart';
import 'push_payload.dart';
import 'push_registrar.dart';

/// Must match the backend's ANDROID_CHANNEL_ID (fcm-push.provider.ts) and
/// the default channel declared in AndroidManifest.xml. Android 8+ drops a
/// notification sent to a channel the app never created, so this one is
/// created on every launch in [PushNotifications.initialize].
const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'lolly_default',
  'Lolly',
  description: 'Matches, messages and Live Snap invites',
  importance: Importance.high,
);

/// FCM requires a registered background handler even when there is
/// nothing to do: the backend sends a `notification` block with every
/// push, so Android renders background/terminated arrivals itself. Must
/// be a top-level function (runs in its own isolate).
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

/// WP7: everything push-related on the device, in one place.
///
///  - [initialize] (before runApp): Firebase, the notification channel,
///    and the three ways a push reaches us (foreground stream, tap on a
///    background push, tap that launched the app).
///  - [PushRegistrar] (called by AuthState): token registration with the
///    backend on login / app start / token refresh, and unregistration
///    on logout.
///  - [attachSession] / [detachSession] (called by main.dart's _AppRoot):
///    the current user id, which every screen a tap can open requires.
///    A tap that arrives before it is known is parked and replayed.
///
/// Never throws out of any public method: push being unavailable (no
/// google-services.json, permission denied, backend down) must never
/// break login or the app itself.
class PushNotifications implements PushRegistrar {
  PushNotifications._();

  static final PushNotifications instance = PushNotifications._();

  /// Set on MaterialApp so a tap can navigate without a BuildContext.
  final navigatorKey = GlobalKey<NavigatorState>();

  final _local = FlutterLocalNotificationsPlugin();
  final _repository = NotificationsRepository();

  bool _available = false;

  /// False when Firebase could not be initialized (no config file).
  bool get isAvailable => _available;

  String? _currentUserId;
  PushPayload? _pendingTap;
  String? _lastRegisteredToken;
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// The connection whose thread is on screen right now, if any. Set and
  /// cleared by MessageThreadScreen; a foreground push for that thread is
  /// redundant (the socket already rendered it) and is not shown.
  String? activeConnectionId;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[push] disabled: Firebase not configured ($e)');
      return;
    }
    _available = true;

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        _handleTap(PushPayload.fromData(_decodeLocalPayload(raw)));
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _handleTap(PushPayload.fromData(message.data)));

    final launchedBy = await FirebaseMessaging.instance.getInitialMessage();
    if (launchedBy != null) _handleTap(PushPayload.fromData(launchedBy.data));
  }

  // ── Token registration (PushRegistrar) ───────────────────────────────

  @override
  Future<void> syncForSignedInUser() async {
    if (!_available) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] permission denied; not registering a token');
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
      _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (refreshed) => _register(refreshed).catchError((Object e) => debugPrint('[push] re-register failed: $e')),
      );
    } catch (e) {
      debugPrint('[push] token sync failed: $e');
    }
  }

  @override
  Future<void> unregisterForSignOut() async {
    if (_available) {
      try {
        final token = _lastRegisteredToken ?? await FirebaseMessaging.instance.getToken();
        if (token != null) await _repository.unregisterDevice(token: token);
      } catch (e) {
        debugPrint('[push] unregister failed: $e');
      }
    }
    _lastRegisteredToken = null;
    detachSession();
  }

  Future<void> _register(String token) async {
    await _repository.registerDevice(token: token, platform: Platform.isIOS ? 'IOS' : 'ANDROID');
    _lastRegisteredToken = token;
  }

  // ── Session (who is signed in) ───────────────────────────────────────

  void attachSession(String userId) {
    _currentUserId = userId;
    final parked = _pendingTap;
    if (parked != null) {
      _pendingTap = null;
      _handleTap(parked);
    }
  }

  void detachSession() {
    _currentUserId = null;
    _pendingTap = null;
    activeConnectionId = null;
  }

  // ── Arrivals ─────────────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final payload = PushPayload.fromData(message.data);
    if (payload != null && !payload.shouldShowInForeground(activeConnectionId: activeConnectionId)) {
      return;
    }
    final notification = message.notification;
    if (notification == null) return;

    // Android does not display a `notification` push while the app is in
    // the foreground; mirror it as a local notification on our channel.
    await _local.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleTap(PushPayload? payload) {
    if (payload == null) return;
    final userId = _currentUserId;
    final navigator = navigatorKey.currentState;
    if (userId == null || navigator == null) {
      // Not signed in yet / widget tree not up yet: replayed by attachSession.
      _pendingTap = payload;
      return;
    }

    switch (payload.destination) {
      case PushDestination.messageThread:
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => MessageThreadScreen(
              connectionId: payload.connectionId,
              currentUserId: userId,
              otherUserId: payload.otherUserId,
              otherDisplayName: payload.otherDisplayName,
            ),
          ),
        );
      case PushDestination.liveSnapCall:
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => LiveSnapCallScreen(
              connectionId: payload.connectionId,
              currentUserId: userId,
              otherUserId: payload.otherUserId,
            ),
          ),
        );
      case PushDestination.home:
        // The tap already brought the app to the front; Discovery shows
        // the new match. Identity is not revealed yet, so there is no
        // specific screen to deep-link into.
        break;
    }
  }

  static Map<String, dynamic> _decodeLocalPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
