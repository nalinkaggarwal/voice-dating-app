import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/config/app_config.dart';
import '../../../demo/demo_backend.dart';
import '../../../shared/api/token_storage.dart';

/// Thin wrapper around the same Socket.IO connection WP4's Live Snap uses
/// (realtime.gateway.ts), but for chat delivery notifications instead of
/// WebRTC signaling. Deliberately dumb: message:new/delivered/read here
/// are broadcast-only notifications the server sends after a REST call
/// already persisted something -- this client never sends a message
/// itself (see MessagingRepository for that). A dropped connection means
/// missed notifications, not lost data: MessageThreadState re-syncs via
/// REST's `since` param on every (re)connect, same reasoning as
/// OnboardingState.resumeFrom's "ask for the latest, don't trust a
/// remembered cursor" pattern.
///
/// In a demo build (AppConfig.demoMode) there is no socket: the same
/// callbacks are fed by DemoBackend's simulated replies instead.
class ChatSocketClient {
  io.Socket? _socket;
  DemoChatListener? _demo;

  Future<void> connect() async {
    if (AppConfig.demoMode) {
      _demo = DemoChatListener();
      DemoBackend.instance.addChatListener(_demo!);
      return;
    }
    final token = await TokenStorage().readAccessToken();
    _socket = io.io(
      AppConfig.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );
    _socket!.connect();
  }

  /// Fires on every successful connect, including reconnects after a
  /// drop -- the one signal MessageThreadState needs to know "go fetch
  /// whatever I might have missed."
  void onConnect(void Function() callback) {
    if (_demo != null) {
      Future.microtask(callback);
      return;
    }
    _socket?.onConnect((_) => callback());
  }

  void onNewMessage(void Function(Map<String, dynamic> payload) callback) {
    if (_demo != null) {
      _demo!.onNewMessage = callback;
      return;
    }
    _socket?.on('message:new', (data) => callback(Map<String, dynamic>.from(data as Map)));
  }

  void onDelivered(void Function(Map<String, dynamic> payload) callback) {
    _socket?.on('message:delivered', (data) => callback(Map<String, dynamic>.from(data as Map)));
  }

  void onRead(void Function(Map<String, dynamic> payload) callback) {
    if (_demo != null) {
      _demo!.onRead = callback;
      return;
    }
    _socket?.on('message:read', (data) => callback(Map<String, dynamic>.from(data as Map)));
  }

  void dispose() {
    if (_demo != null) DemoBackend.instance.removeChatListener(_demo!);
    _demo = null;
    _socket?.dispose();
    _socket = null;
  }
}
