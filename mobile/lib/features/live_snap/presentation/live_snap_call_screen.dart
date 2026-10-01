import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../messaging/presentation/message_thread_screen.dart';
import '../application/live_snap_state.dart';
import '../domain/live_snap_models.dart';

class LiveSnapCallScreen extends StatelessWidget {
  const LiveSnapCallScreen({super.key, required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LiveSnapState(connectionId: connectionId)..start(),
      child: _LiveSnapBody(connectionId: connectionId, currentUserId: currentUserId),
    );
  }
}

class _LiveSnapBody extends StatelessWidget {
  const _LiveSnapBody({required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  Future<void> _handleDecline(BuildContext context, LiveSnapState state) async {
    await state.declineMatch();
    // Nothing left to do on this connection -- straight back to
    // Discovery, skipping Match/Reveal/Call.
    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _handleConfirm(BuildContext context, LiveSnapState state) async {
    final matched = await state.confirmMatch();
    if (!context.mounted) return;
    if (matched) {
      // Both sides have now confirmed -- AUTHENTICATED_MATCH just fired,
      // so there's somewhere real to go: straight into the new chat
      // thread rather than back to Discovery with no obvious next step.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MessageThreadScreen(connectionId: connectionId, currentUserId: currentUserId),
        ),
        (route) => route.isFirst,
      );
      return;
    }
    // Confirmed, but the other side hasn't yet -- nothing to show here
    // until they do; back to Discovery same as a decline.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LiveSnapState>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Live Snap')),
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, LiveSnapState state) {
    switch (state.status) {
      case LiveSnapCallStatus.requestingPermission:
        return const Center(child: CircularProgressIndicator());

      case LiveSnapCallStatus.permissionDenied:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Camera and microphone access is needed for Live Snap.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                _OpenSettingsButton(),
              ],
            ),
          ),
        );

      case LiveSnapCallStatus.waiting:
      case LiveSnapCallStatus.connecting:
      case LiveSnapCallStatus.active:
        return Stack(
          children: [
            Positioned.fill(child: RTCVideoView(state.remoteRenderer)),
            Positioned(
              right: 16,
              top: 16,
              width: 110,
              height: 150,
              child: RTCVideoView(state.localRenderer, mirror: true),
            ),
            if (state.status != LiveSnapCallStatus.active)
              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    state.status == LiveSnapCallStatus.waiting
                        ? 'Waiting for your match to join...'
                        : 'Connecting...',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: state.endCall,
                  child: const Icon(Icons.call_end),
                ),
              ),
            ),
          ],
        );

      case LiveSnapCallStatus.ended:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Call ended. Was this a good match?',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton(
                      onPressed: () => _handleDecline(context, state),
                      child: const Text('Not a match'),
                    ),
                    FilledButton(
                      onPressed: () => _handleConfirm(context, state),
                      child: const Text('Confirm match'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// Pulled out so the surrounding permissionDenied children list can stay
/// `const` -- OutlinedButton itself isn't const-constructible.
class _OpenSettingsButton extends StatelessWidget {
  const _OpenSettingsButton();

  @override
  Widget build(BuildContext context) {
    return const OutlinedButton(onPressed: openAppSettings, child: Text('Open settings'));
  }
}
