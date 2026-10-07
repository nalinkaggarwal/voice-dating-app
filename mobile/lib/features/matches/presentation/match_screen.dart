import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: brandGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Center(child: LollyMark(size: 128, style: LollyMarkStyle.onGradient)),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  "It's a match",
                  textAlign: TextAlign.center,
                  style: textTheme.headlineLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "You're both interested. Still no names or photos -- that's the next step, together.",
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const Spacer(),
                FilledButton(
                  style: AppTheme.accentButton(scheme),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RevealScreen(connectionId: connectionId, currentUserId: currentUserId),
                    ),
                  ),
                  child: const Text('See who it is'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Maybe later'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
