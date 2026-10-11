import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/onboarding_state.dart';
import 'onboarding_progress.dart';

/// Backend enum value -> (emoji, title, subtitle).
const _intentOptions = <String, (String, String, String)>{
  'LONG_TERM': ('💞', 'Something serious', 'Looking for a real, long-term relationship'),
  'SHORT_TERM': ('🔥', 'Something casual', 'Fun dates, good vibes, no pressure'),
  'NOT_SURE_YET': ('🌱', 'Not sure yet', 'Open to seeing where things go'),
};

class IntentStep extends StatefulWidget {
  const IntentStep({super.key});

  @override
  State<IntentStep> createState() => _IntentStepState();
}

class _IntentStepState extends State<IntentStep> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    return OnboardingScaffold(
      step: onboardingStepNumber(state.currentStep),
      totalSteps: kOnboardingStepCount,
      emoji: '🎯',
      title: 'What are you looking for?',
      subtitle: 'Be honest. It helps us match you with people who want the same thing.',
      errorMessage: state.errorMessage,
      primaryLabel: 'Continue',
      loading: state.isLoading,
      onPrimary: _selected == null ? null : () => state.submitIntent(_selected!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in _intentOptions.entries) ...[
            ChoiceCard(
              emoji: entry.value.$1,
              title: entry.value.$2,
              subtitle: entry.value.$3,
              selected: _selected == entry.key,
              onTap: () => setState(() => _selected = entry.key),
            ),
            const SizedBox(height: AppSpacing.sm + 4),
          ],
        ],
      ),
    );
  }
}
