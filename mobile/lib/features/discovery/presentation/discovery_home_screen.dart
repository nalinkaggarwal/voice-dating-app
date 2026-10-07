import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/voice_clip_player.dart';
import '../../auth/application/auth_state.dart';
import '../../matches/presentation/match_screen.dart';
import '../../messaging/presentation/conversations_list_screen.dart';
import '../application/discovery_state.dart';
import '../domain/discovery_entry.dart';

/// Entry point into WP3 discovery -- shows today's ONE curated candidate
/// (or more than one, for a tier with dailyCandidateLimit > 1; see
/// DiscoveryConfig on the backend). Deliberately not a swipe feed: no
/// stack of cards, no browsing ahead -- just the next undecided entry,
/// same shape as the backend's queue.
class DiscoveryHomeScreen extends StatelessWidget {
  const DiscoveryHomeScreen({super.key, required this.currentUserId});

  /// Needed to tell "my message" from "their message" in a thread --
  /// threaded down from main.dart's single already-fetched User rather
  /// than each messaging screen re-fetching it independently.
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DiscoveryState()..loadToday(),
      child: _DiscoveryBody(currentUserId: currentUserId),
    );
  }
}

class _DiscoveryBody extends StatelessWidget {
  const _DiscoveryBody({required this.currentUserId});

  final String currentUserId;

  Future<void> _handleDecision(
    BuildContext context,
    DiscoveryState state,
    DiscoveryDecision decision,
  ) async {
    final result = await state.decide(decision);
    if (result.matched && result.connectionId != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MatchScreen(connectionId: result.connectionId!, currentUserId: currentUserId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DiscoveryState>();

    return Scaffold(
      appBar: AppBar(
        title: const AppWordmark(withMark: true, fontSize: 22),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'Messages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ConversationsListScreen(currentUserId: currentUserId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthState>().logout(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          child: _buildBody(context, state),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoveryState state) {
    if (state.isLoading && state.currentEntry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.currentEntry == null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load today's voice",
        body: state.errorMessage,
        action: OutlinedButton(onPressed: state.loadToday, child: const Text('Try again')),
      );
    }

    final entry = state.currentEntry;
    if (entry == null) {
      return const EmptyState(
        icon: Icons.nightlight_round,
        title: "You're all caught up",
        body: 'Your next voice arrives tomorrow. One a day keeps it real.',
      );
    }

    return _CandidateCard(
      entry: entry,
      isDeciding: state.isLoading,
      errorMessage: state.errorMessage,
      onPass: () => _handleDecision(context, state, DiscoveryDecision.pass),
      onInterested: () => _handleDecision(context, state, DiscoveryDecision.interested),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.entry,
    required this.isDeciding,
    required this.errorMessage,
    required this.onPass,
    required this.onInterested,
  });

  final DiscoveryEntry entry;
  final bool isDeciding;
  final String? errorMessage;
  final VoidCallback onPass;
  final VoidCallback onInterested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                // No photo, no name -- deliberately. "Hear before you see"
                // is the whole premise; a candidate's identity is never
                // shown before a decision (see DiscoveryEntry's own
                // docstring). The waveform silhouette stands for "someone
                // new", not a preview of anyone.
                const _VoiceHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Someone new', style: theme.textTheme.titleLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'No name, no photo yet. Just listen.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (entry.voiceClipUrl != null)
                          // Keyed on the entry -- without this, advancing to
                          // the next candidate would reuse the previous
                          // VoiceClipPlayer's State (same widget position in
                          // the tree), potentially leaving a stale "playing"
                          // indicator or a still-running player from the
                          // PREVIOUS candidate's clip.
                          VoiceClipPlayer(
                            key: ValueKey(entry.id),
                            source: UrlSource(entry.voiceClipUrl!),
                            iconSize: 44,
                          )
                        else
                          Text(
                            'No voice intro available yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.tertiary),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: Text(entry.reasonText, style: theme.textTheme.bodyMedium)),
                            ],
                          ),
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(errorMessage!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RoundAction(
              icon: Icons.close_rounded,
              label: 'Pass',
              size: 64,
              onTap: isDeciding ? null : onPass,
            ),
            const SizedBox(width: AppSpacing.xxl),
            _RoundAction(
              icon: Icons.favorite_rounded,
              label: 'Interested',
              size: 76,
              accent: true,
              onTap: isDeciding ? null : onInterested,
            ),
          ],
        ),
      ],
    );
  }
}

class _VoiceHeader extends StatelessWidget {
  const _VoiceHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(gradient: brandGradient()),
      child: Stack(
        children: [
          Positioned(
            left: AppSpacing.md,
            top: AppSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Text(
                "TODAY'S VOICE",
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
              ),
              child: const Icon(Icons.graphic_eq_rounded, size: 56, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.size,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final background = accent ? scheme.tertiary : scheme.surfaceContainerHigh;
    final foreground = accent ? scheme.onTertiary : scheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: background,
            shape: CircleBorder(
              side: accent ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, size: size * 0.46, color: foreground),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
