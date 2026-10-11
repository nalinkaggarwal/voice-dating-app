import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/branding.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../auth/application/auth_state.dart';
import '../../discovery/presentation/discovery_home_screen.dart';

class OnboardingCompleteStep extends StatelessWidget {
  const OnboardingCompleteStep({super.key, required this.currentUserId, this.onFinished});

  final String currentUserId;

  /// See OnboardingFlowScreen.onFinished.
  final VoidCallback? onFinished;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: AuroraBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(Icons.logout_rounded),
                            tooltip: 'Log out',
                            onPressed: () => context.read<AuthState>().logout(),
                          ),
                        ),
                        const Spacer(),
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(36),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.magenta.withValues(alpha: 0.6),
                                  blurRadius: 70,
                                  spreadRadius: -4,
                                ),
                              ],
                            ),
                            child: const LollyMark(
                              size: 132,
                              style: LollyMarkStyle.onGradient,
                              withBackground: true,
                              inset: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text("You're all set 🎉", textAlign: TextAlign.center, style: textTheme.displaySmall),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Your voice is ready. Time to hear your first match.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const Center(
                          child: VoiceWaveform(
                            active: true,
                            barCount: 9,
                            height: 30,
                            barWidth: 4,
                            gap: 4,
                            color: AppTheme.coral,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: AppSpacing.xl),
                        GradientButton(
                          label: 'Start discovering',
                          icon: Icons.headphones_rounded,
                          onPressed: () {
                            // Let the app root switch to Discovery. Never
                            // pushReplacement here: this step IS the root
                            // route, and replacing it removed the widget
                            // that reacts to logout ("log out does nothing").
                            final finished = onFinished;
                            if (finished != null) {
                              finished();
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => DiscoveryHomeScreen(currentUserId: currentUserId)),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
