import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/error/app_exception.dart';
import '../data/live_snap_repository.dart';
import '../data/signaling_client.dart';
import '../domain/live_snap_models.dart';

/// Owns the whole Live Snap call lifecycle: camera/mic permission, the
/// WebRTC peer connection, and the signaling socket that negotiates it.
/// One instance per call attempt -- a retried call (after "ended") means
/// building a new LiveSnapState, not reusing this one.
class LiveSnapState extends ChangeNotifier {
  LiveSnapState({
    required this.connectionId,
    LiveSnapRepository? repository,
    SignalingClient? signaling,
  })  : _repository = repository ?? LiveSnapRepository(),
        _signaling = signaling ?? SignalingClient();

  final String connectionId;
  final LiveSnapRepository _repository;
  final SignalingClient _signaling;

  LiveSnapCallStatus status = LiveSnapCallStatus.requestingPermission;
  String? errorMessage;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  String? _sessionId;
  bool _disposed = false;

  static const _mediaConstraints = {
    'audio': true,
    'video': {'facingMode': 'user'},
  };

  Future<void> start() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    status = LiveSnapCallStatus.requestingPermission;
    _notify();

    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      status = LiveSnapCallStatus.permissionDenied;
      _notify();
      return;
    }

    try {
      final startResult = await _repository.startSession(connectionId);
      _sessionId = startResult.sessionId;

      _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);
      localRenderer.srcObject = _localStream;

      _peerConnection = await createPeerConnection({
        'iceServers': startResult.iceServers.map((s) => s.toMap()).toList(),
      });
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
      _peerConnection!.onIceCandidate = (candidate) {
        _signaling.sendIceCandidate(connectionId, _sessionId!, candidate.toMap());
      };
      _peerConnection!.onTrack = (event) {
        if (event.streams.isEmpty) return;
        remoteRenderer.srcObject = event.streams.first;
        status = LiveSnapCallStatus.active;
        _notify();
      };

      await _signaling.connect();
      _signaling.onPeerJoined(_handlePeerJoined);
      _signaling.onOffer(_handleOffer);
      _signaling.onAnswer(_handleAnswer);
      _signaling.onIceCandidate(_handleRemoteIceCandidate);
      _signaling.onPeerLeft(_handlePeerLeft);

      status = LiveSnapCallStatus.waiting;
      _notify();
      _signaling.join(connectionId, _sessionId!);
    } on AppException catch (e) {
      errorMessage = e.message;
      _notify();
    }
  }

  Future<void> _handlePeerJoined(bool shouldOffer) async {
    status = LiveSnapCallStatus.connecting;
    _notify();
    // Only the side the server designated creates the offer -- the other
    // side just waits for it. See realtime.gateway.ts's handleJoin.
    if (!shouldOffer) return;
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _signaling.sendOffer(connectionId, _sessionId!, offer.toMap());
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?),
    );
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _signaling.sendAnswer(connectionId, _sessionId!, answer.toMap());
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?),
    );
  }

  Future<void> _handleRemoteIceCandidate(Map<String, dynamic> payload) async {
    await _peerConnection!.addCandidate(
      RTCIceCandidate(
        payload['candidate'] as String?,
        payload['sdpMid'] as String?,
        payload['sdpMLineIndex'] as int?,
      ),
    );
  }

  void _handlePeerLeft() {
    status = LiveSnapCallStatus.ended;
    _notify();
  }

  /// Ends the call locally and tells the other side -- an explicit
  /// "end call" tap. Deliberately separate from confirm/decline: ending
  /// the call is not itself a verdict on the match, just how you get to
  /// the screen that asks for one.
  void endCall() {
    if (_sessionId != null) {
      _signaling.leave(connectionId, _sessionId!);
    }
    status = LiveSnapCallStatus.ended;
    _notify();
  }

  Future<bool> confirmMatch() => _runConnectionAction(() => _repository.confirm(connectionId));

  Future<bool> declineMatch() => _runConnectionAction(() async {
        await _repository.decline(connectionId);
        return true;
      });

  Future<bool> _runConnectionAction(Future<bool> Function() action) async {
    try {
      return await action();
    } on AppException catch (e) {
      errorMessage = e.message;
      _notify();
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _signaling.dispose();
    _peerConnection?.close();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
