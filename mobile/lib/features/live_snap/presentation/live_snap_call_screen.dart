import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../messaging/presentation/message_thread_screen.dart';
import '../../trust_safety/domain/report_reason.dart';
import '../../trust_safety/presentation/trust_safety_actions.dart';
import '../application/live_snap_state.dart';
import '../domain/live_snap_models.dart';

class LiveSnapCallScreen extends StatelessWidget {
  const LiveSnapCallScreen({
    super.key,
    required this.connectionId,
    required this.currentUserId,
    required this.otherUserId,
  });

  final String connectionId;
  final String currentUserId;
  final String otherUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LiveSnapState(connectionId: connectionId)..start(),
      child: _LiveSnapBody(connectionId: connectionId, currentUserId: currentUserId, otherUserId: otherUserId),
    );
  }
}

class _LiveSnapBody extends StatelessWidget {
  const _LiveSnapBody({required this.connectionId, required this.currentUserId, required this.otherUserId});

  final String connectionId;
  final String currentUserId;
  final String otherUserId;

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
          builder: (_) => MessageThreadScreen(
          connectionId: connectionId,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
        ),
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
      backgroundColor: AppTheme.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, color: AppTheme.coral, size: 22),
            SizedBox(width: AppSpacing.sm),
            Text('Live Snap'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report',
            onPressed: () => showReportDialog(
              context,
              reportedUserId: otherUserId,
              reportContext: ReportContext.liveSnap,
              contextId: state.sessionId,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, LiveSnapState state) {
    switch (state.status) {
      case LiveSnapCallStatus.requestingPermission:
        return const AuroraBackground(
          intensity: 0.6,
          child: Center(child: CircularProgressIndicator()),
        );

      case LiveSnapCallStatus.permissionDenied:
        return const AuroraBackground(
          intensity: 0.6,
          child: SafeArea(
            child: _CenteredScroll(
              children: [
                _IconBadge(icon: Icons.videocam_off_rounded),
                SizedBox(height: AppSpacing.lg),
                Text(
                  'Camera and microphone access is needed for Live Snap.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.lg),
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
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            Positioned.fill(child: RTCVideoView(state.remoteRenderer)),
            // Scrims top and bottom so the app bar and controls stay
            // legible over any video.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 260,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      right: AppSpacing.md,
                      top: AppSpacing.md,
                      width: 110,
                      height: 150,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md + 2),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: RTCVideoView(
                            state.localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                    ),
                    if (state.status != LiveSnapCallStatus.active)
                      Positioned(
                        bottom: 128,
                        left: AppSpacing.lg,
                        right: AppSpacing.lg,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2, vertical: AppSpacing.sm + 4),
                            decoration: BoxDecoration(
                              color: AppTheme.surface1.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                              border: Border.all(color: AppTheme.stroke),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const VoiceWaveform(
                                  active: true,
                                  barCount: 5,
                                  height: 18,
                                  barWidth: 3,
                                  gap: 3,
                                  color: AppTheme.coral,
                                ),
                                const SizedBox(width: AppSpacing.sm + 2),
                                Flexible(
                                  child: Text(
                                    state.status == LiveSnapCallStatus.waiting
                                        ? 'Waiting for your match to join...'
                                        : 'Connecting...',
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontFamily,
                                      color: AppTheme.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: AppSpacing.xl,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _EndCallButton(onPressed: state.endCall),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

      case LiveSnapCallStatus.ended:
        return AuroraBackground(
          child: SafeArea(
            child: _CenteredScroll(
              children: [
                const _IconBadge(icon: Icons.favorite_rounded, gradient: true),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Call ended. Was this a good match?',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Confirm only if it felt right. Chat opens when you both do.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  ErrorBanner(state.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.xl),
                GradientButton(
                  label: 'Confirm match',
                  icon: Icons.favorite_rounded,
                  onPressed: () => _handleConfirm(context, state),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                OutlinedButton(
                  onPressed: () => _handleDecline(context, state),
                  child: const Text('Not a match'),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// Vertically centred column that scrolls instead of overflowing.
class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.gradient = false});

  final IconData icon;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient ? brandGradient() : null,
          color: gradient ? null : AppTheme.surface2,
          border: gradient ? null : Border.all(color: AppTheme.stroke),
          boxShadow: gradient
              ? [BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: -4)]
              : null,
        ),
        child: Icon(icon, size: 44, color: gradient ? Colors.white : AppTheme.coralLight),
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Tooltip(
      message: 'End call',
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: error,
          boxShadow: [BoxShadow(color: error.withValues(alpha: 0.5), blurRadius: 28, spreadRadius: -4)],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
      ),
    );
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
