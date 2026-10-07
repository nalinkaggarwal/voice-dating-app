import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../live_snap/presentation/live_snap_call_screen.dart';
import '../../trust_safety/domain/report_reason.dart';
import '../../trust_safety/presentation/trust_safety_actions.dart';
import '../application/reveal_state.dart';
import '../domain/reveal_profile.dart';

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
      appBar: AppBar(
        title: const Text('Your match'),
        actions: profile == null
            ? null
            : [
                PopupMenuButton<String>(
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildBody(context, state),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RevealState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: profile?.photoUrl != null
                      ? Image.network(profile!.photoUrl!, fit: BoxFit.cover)
                      : DecoratedBox(
                          decoration: BoxDecoration(gradient: brandGradient()),
                          child: const Icon(Icons.person_rounded, size: 96, color: Colors.white),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          profile?.displayName ?? 'Your match',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_rounded, size: 18, color: scheme.tertiary),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                'Next: a quick live video check together. Then chat unlocks.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(state.errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: state.isLoading ? null : () => _decline(context, state),
                child: const Text('Not for me'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: AppTheme.accentButton(scheme),
                onPressed: state.isLoading || profile == null ? null : () => _startLiveSnap(context, profile.userId),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Start Live Snap'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
