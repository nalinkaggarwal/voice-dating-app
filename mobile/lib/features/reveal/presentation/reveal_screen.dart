import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../live_snap/presentation/live_snap_call_screen.dart';
import '../../trust_safety/domain/report_reason.dart';
import '../../trust_safety/presentation/trust_safety_actions.dart';
import '../application/reveal_state.dart';
import '../domain/reveal_profile.dart';
import '../../../shared/widgets/media_sources.dart';

/// Mutual Reveal -- the matched user's name/photo, shown for the first
/// time now that there's a real mutual match. Sits between the "You
/// matched!" screen and the Live Snap call: seeing a photo first lets
/// someone back out before committing to a live call, matching the
/// product's own pipeline (... -> Mutual Reveal -> Live Snap -> ...).
class RevealScreen extends StatelessWidget {
  const RevealScreen({super.key, required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RevealState()..load(connectionId),
      child: _RevealBody(connectionId: connectionId, currentUserId: currentUserId),
    );
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  Future<void> _decline(BuildContext context, RevealState state) async {
    final declined = await state.decline(connectionId);
    if (declined && context.mounted) {
      // Back to Discovery directly -- no reason to pass back through the
      // "You matched!" screen for a match just declined.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _startLiveSnap(BuildContext context, String otherUserId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveSnapCallScreen(
          connectionId: connectionId,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
        ),
      ),
    );
  }

  Future<void> _handleBlock(BuildContext context, RevealProfile profile) async {
    final blocked = await confirmAndBlockUser(context, userId: profile.userId);
    if (blocked && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RevealState>();
    final profile = state.profile;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Your match'),
        actions: profile == null
            ? null
            : [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (value) {
                    if (value == 'report') {
                      showReportDialog(context, reportedUserId: profile.userId, reportContext: ReportContext.profile);
                    } else if (value == 'block') {
                      _handleBlock(context, profile);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'report', child: Text('Report')),
                    PopupMenuItem(value: 'block', child: Text('Block')),
                  ],
                ),
              ],
      ),
      body: AuroraBackground(
        intensity: 0.7,
        child: SafeArea(child: _buildBody(context, state)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RevealState state) {
    final theme = Theme.of(context);

    if (state.isLoading && state.profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.profile == null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load your match",
        body: state.errorMessage,
        action: OutlinedButton(onPressed: () => state.load(connectionId), child: const Text('Try again')),
      );
    }

    final profile = state.profile;
    // Photo grows to fill a tall screen; on a short one the whole page
    // scrolls instead of overflowing.
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: _PhotoCard(
                          photoUrl: profile?.photoUrl,
                          name: profile?.displayName ?? 'Your match',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_rounded, size: 18, color: AppTheme.coral),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Flexible(
                      child: Text(
                        'Next: a quick live video check together. Then chat unlocks.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  ErrorBanner(state.errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                GradientButton(
                  label: 'Start Live Snap',
                  icon: Icons.videocam_rounded,
                  onPressed: state.isLoading || profile == null ? null : () => _startLiveSnap(context, profile.userId),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                OutlinedButton(
                  onPressed: state.isLoading ? null : () => _decline(context, state),
                  child: const Text('Not for me'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The reveal itself: photo in a Bloom-gradient frame with a soft glow,
/// name set over a dark scrim at the bottom.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl + 2),
        gradient: brandGradient(),
        boxShadow: [
          BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.35), blurRadius: 48, spreadRadius: -8),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photoUrl != null)
              Image(image: imageProviderFor(photoUrl!), fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(gradient: brandGradient()),
                child: const Icon(Icons.person_rounded, size: 96, color: Colors.white),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, AppTheme.ink.withValues(alpha: 0.85)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.lg),
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.headlineMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4, vertical: AppSpacing.xs + 2),
                decoration: BoxDecoration(
                  color: AppTheme.ink.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.amber),
                    SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      'REVEALED',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
