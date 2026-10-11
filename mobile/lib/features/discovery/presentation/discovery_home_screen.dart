import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/voice_clip_player.dart';
import '../../auth/application/auth_state.dart';
import '../../matches/presentation/match_screen.dart';
import '../../messaging/presentation/conversations_list_screen.dart';
import '../application/discovery_state.dart';
import '../domain/discovery_entry.dart';
import '../../../shared/widgets/media_sources.dart';

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
      backgroundColor: AppTheme.ink,
      body: AuroraBackground(
        intensity: 0.6,
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                onMessages: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ConversationsListScreen(currentUserId: currentUserId)),
                ),
                onLogout: () => context.read<AuthState>().logout(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                  child: _buildBody(context, state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoveryState state) {
    if (state.isLoading && state.currentEntry == null) {
      return const _TuningIn();
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

/// Mark + wordmark on the left, round glass icon buttons on the right --
/// replaces the stock Material AppBar.
class _Header extends StatelessWidget {
  const _Header({required this.onMessages, required this.onLogout});

  final VoidCallback onMessages;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AppWordmark(withMark: true, fontSize: 24),
            ),
          ),
          const Spacer(),
          _GlassIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Messages',
            onPressed: onMessages,
          ),
          const SizedBox(width: AppSpacing.sm),
          _GlassIconButton(
            icon: Icons.logout_rounded,
            tooltip: 'Log out',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(46),
        backgroundColor: AppTheme.surface1.withValues(alpha: 0.8),
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: AppTheme.stroke),
      ),
    );
  }
}

/// Loading state: a breathing waveform instead of a bare spinner.
class _TuningIn extends StatelessWidget {
  const _TuningIn();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VoiceWaveform(active: true, barCount: 9, height: 56, barWidth: 6, gap: 5, color: AppTheme.coral),
            const SizedBox(height: AppSpacing.lg),
            Text("Tuning in today's voice", style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('One person, picked for you.', style: textTheme.bodyMedium),
          ],
        ),
      ),
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

    return Column(
      children: [
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.surface1.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppTheme.stroke),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.plum.withValues(alpha: 0.25),
                  blurRadius: 48,
                  spreadRadius: -12,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            // Scrolls inside the card so a short screen never overflows;
            // the like/pass row below stays pinned and reachable.
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // No photo, no name -- deliberately. "Hear before you see"
                  // is the whole premise; a candidate's identity is never
                  // shown before a decision (see DiscoveryEntry's own
                  // docstring). The waveform silhouette stands for "someone
                  // new", not a preview of anyone.
                  const _VoiceHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Someone new', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'No name, no photo yet. Just listen.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppTheme.surface2,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            border: Border.all(color: AppTheme.stroke),
                          ),
                          alignment: Alignment.center,
                          child: entry.voiceClipUrl != null
                              // Keyed on the entry -- without this, advancing to
                              // the next candidate would reuse the previous
                              // VoiceClipPlayer's State (same widget position in
                              // the tree), potentially leaving a stale "playing"
                              // indicator or a still-running player from the
                              // PREVIOUS candidate's clip.
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: VoiceClipPlayer(
                                    key: ValueKey(entry.id),
                                    source: audioSourceFor(entry.voiceClipUrl!),
                                    iconSize: 44,
                                  ),
                                )
                              : Text(
                                  'No voice intro available yet.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ReasonChip(text: entry.reasonText),
                        if (errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          ErrorBanner(errorMessage!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
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
              size: 80,
              accent: true,
              onTap: isDeciding ? null : onInterested,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Why you two" -- the match reason, in a warm-tinted callout.
class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.magenta.withValues(alpha: 0.14), AppTheme.amber.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: AppTheme.magenta.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => brandGradient().createShader(bounds),
            child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(text, style: textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _VoiceHeader extends StatelessWidget {
  const _VoiceHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(gradient: brandGradient()),
      child: Stack(
        children: [
          // Soft dark vignette at the bottom so the card body reads as
          // one surface with the hero.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppTheme.ink.withValues(alpha: 0.35)],
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            top: AppSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4, vertical: AppSpacing.xs + 2),
              decoration: BoxDecoration(
                color: AppTheme.ink.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq_rounded, size: 14, color: Colors.white),
                  SizedBox(width: AppSpacing.xs + 2),
                  Text(
                    "TODAY'S VOICE",
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
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.18), blurRadius: 40, spreadRadius: 4),
                ],
              ),
              alignment: Alignment.center,
              child: const VoiceWaveform(
                active: false,
                barCount: 7,
                height: 52,
                barWidth: 6,
                gap: 5,
                color: Colors.white,
              ),
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
    final enabled = onTap != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: accent ? brandGradient() : null,
              color: accent ? null : AppTheme.surface2,
              border: accent ? null : Border.all(color: const Color(0x33FFFFFF), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: accent ? AppTheme.magenta.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.35),
                  blurRadius: accent ? 32 : 18,
                  spreadRadius: accent ? -4 : -6,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Icon(
                  icon,
                  size: size * 0.44,
                  color: accent ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(color: accent ? AppTheme.textPrimary : AppTheme.textMuted),
        ),
      ],
    );
  }
}
