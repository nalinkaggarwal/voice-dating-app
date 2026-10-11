import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../reveal/presentation/reveal_screen.dart';

/// Mutual-match confirmation, shown right after a decide() call flips a
/// Connection to MUTUAL_INTEREST. Still no name or photo here -- same
/// "hear before you see" rule that governs the discovery card itself --
/// but WP4 wires the CTA forward into Mutual Reveal (name/photo) and then
/// Live Snap (a live video check) rather than just dismissing.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key, required this.connectionId, required this.currentUserId});

  final String connectionId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: AuroraBackground(
        child: SafeArea(
          // Fills the screen on tall phones (Spacers centre the hero),
          // scrolls on short ones instead of overflowing.
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      const Center(child: FittedBox(fit: BoxFit.scaleDown, child: _MatchHero())),
                      const SizedBox(height: AppSpacing.xl),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                          decoration: BoxDecoration(
                            color: AppTheme.magenta.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            border: Border.all(color: AppTheme.magenta.withValues(alpha: 0.35)),
                          ),
                          child: const Text(
                            'MUTUAL INTEREST',
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                              color: Color(0xFFFF8AC2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ShaderMask(
                        shaderCallback: (bounds) => brandGradient().createShader(bounds),
                        child: Text(
                          "It's a match",
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall?.copyWith(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm + 4),
                      Text(
                        "You're both interested. Still no names or photos -- that's the next step, together.",
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted),
                      ),
                      const Spacer(),
                      const SizedBox(height: AppSpacing.xl),
                      GradientButton(
                        label: 'See who it is',
                        icon: Icons.visibility_rounded,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RevealScreen(connectionId: connectionId, currentUserId: currentUserId),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Maybe later'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two voices meeting: a waveform either side of a glowing Bloom disc
/// holding the mark, inside soft concentric rings.
class _MatchHero extends StatelessWidget {
  const _MatchHero();

  @override
  Widget build(BuildContext context) {
    Widget ring(double size, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.coral.withValues(alpha: alpha), width: 1.5),
          ),
        );

    return SizedBox(
      width: 300,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ring(236, 0.10),
          ring(196, 0.18),
          Container(
            width: 152,
            height: 152,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: brandGradient(),
              boxShadow: [
                BoxShadow(color: AppTheme.magenta.withValues(alpha: 0.55), blurRadius: 60, spreadRadius: 2),
              ],
            ),
            alignment: Alignment.center,
            child: const LollyMark(size: 104, style: LollyMarkStyle.onGradient),
          ),
          const Positioned(
            left: 0,
            child: VoiceWaveform(active: false, barCount: 5, height: 40, barWidth: 4, gap: 4, color: AppTheme.coralLight),
          ),
          const Positioned(
            right: 0,
            child: VoiceWaveform(active: false, barCount: 5, height: 40, barWidth: 4, gap: 4, color: AppTheme.amber),
          ),
          const Positioned(
            top: 18,
            right: 58,
            child: Icon(Icons.favorite_rounded, color: AppTheme.magenta, size: 26),
          ),
          Positioned(
            bottom: 22,
            left: 60,
            child: Icon(Icons.favorite_rounded, color: AppTheme.amber.withValues(alpha: 0.8), size: 18),
          ),
        ],
      ),
    );
  }
}
