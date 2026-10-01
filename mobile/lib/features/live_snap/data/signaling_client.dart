import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/config/app_config.dart';
import '../../../shared/api/token_storage.dart';

/// Thin wrapper around the Socket.IO connection used for Live Snap's
/// WebRTC signaling (offer/answer/ICE relay) -- see realtime.gateway.ts's
/// liveSnap:* events on the backend. Deliberately dumb: every method here
/// is a direct emit/on pass-through, no retry/reconnect logic of its own
/// (a dropped call is surfaced to the user as "call ended", not silently
/// recovered -- see LiveSnapState).
class SignalingClient {
  io.Socket? _socket;

  Future<void> connect() async {
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

  void join(String connectionId, String sessionId) {
    _socket?.emit('liveSnap:join', {'connectionId': connectionId, 'sessionId': sessionId});
  }

  void sendOffer(String connectionId, String sessionId, Map<String, dynamic> payload) {
    _socket?.emit('liveSnap:offer', {'connectionId': connectionId, 'sessionId': sessionId, 'payload': payload});
  }

  void sendAnswer(String connectionId, String sessionId, Map<String, dynamic> payload) {
    _socket?.emit('liveSnap:answer', {'connectionId': connectionId, 'sessionId': sessionId, 'payload': payload});
  }

  void sendIceCandidate(String connectionId, String sessionId, Map<String, dynamic> payload) {
    _socket?.emit(
      'liveSnap:ice-candidate',
      {'connectionId': connectionId, 'sessionId': sessionId, 'payload': payload},
    );
  }

  void leave(String connectionId, String sessionId) {
    _socket?.emit('liveSnap:leave', {'connectionId': connectionId, 'sessionId': sessionId});
  }

  /// `shouldOffer` is true only for the second of the pair to join the
  /// signaling room -- see realtime.gateway.ts's handleJoin. Avoids both
  /// sides racing to send a WebRTC offer at once.
  void onPeerJoined(void Function(bool shouldOffer) callback) {
    _socket?.on('liveSnap:peerJoined', (data) {
      callback((data as Map)['shouldOffer'] as bool? ?? false);
    });
  }

  void onPeerLeft(void Function() callback) {
    _socket?.on('liveSnap:peerLeft', (_) => callback());
  }

  void onOffer(void Function(Map<String, dynamic> payload) callback) {
    _socket?.on('liveSnap:offer', (data) => callback(Map<String, dynamic>.from(data as Map)));
  }

  void onAnswer(void Function(Map<String, dynamic> payload) callback) {
    _socket?.on('liveSnap:answer', (data) => callback(Map<String, dynamic>.from(data as Map)));
  }

  void onIceCandidate(void Function(Map<String, dynamic> payload) callback) {
    _socket?.on('liveSnap:ice-candidate', (data) => callback(Map<String, dynamic>.from(data as Map)));
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
