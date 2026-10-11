import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../application/onboarding_state.dart';
import 'onboarding_progress.dart';

/// Backend enum value -> (label, emoji) shown to the user.
const _genderOptions = <String, (String, String)>{
  'MEN': ('Men', '👨'),
  'WOMEN': ('Women', '👩'),
  'NON_BINARY': ('Non-binary', '🌈'),
};

class PreferencesStep extends StatefulWidget {
  const PreferencesStep({super.key});

  @override
  State<PreferencesStep> createState() => _PreferencesStepState();
}

class _PreferencesStepState extends State<PreferencesStep> {
  final Set<String> _selectedGenders = {};
  RangeValues _ageRange = const RangeValues(25, 40);
  double _maxDistanceKm = 50;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final allSelected = _selectedGenders.length == _genderOptions.length;

    return OnboardingScaffold(
      step: onboardingStepNumber(state.currentStep),
      totalSteps: kOnboardingStepCount,
      emoji: '💘',
      title: 'Who do you want to meet?',
      subtitle: 'Pick as many as you like. You can change this anytime.',
      errorMessage: state.errorMessage,
      primaryLabel: 'Continue',
      loading: state.isLoading,
      onPrimary: _selectedGenders.isEmpty
          ? null
          : () => state.submitPreferences(
                genderInterest: _selectedGenders.toList(),
                ageMin: _ageRange.start.round(),
                ageMax: _ageRange.end.round(),
                maxDistanceKm: _maxDistanceKm.round(),
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in _genderOptions.entries)
                ChoicePill(
                  label: entry.value.$1,
                  emoji: entry.value.$2,
                  selected: _selectedGenders.contains(entry.key),
                  onTap: () => setState(() {
                    _selectedGenders.contains(entry.key)
                        ? _selectedGenders.remove(entry.key)
                        : _selectedGenders.add(entry.key);
                  }),
                ),
              ChoicePill(
                label: 'Everyone',
                emoji: '✨',
                selected: allSelected,
                onTap: () => setState(() {
                  allSelected ? _selectedGenders.clear() : _selectedGenders.addAll(_genderOptions.keys);
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledValue(
                  label: 'Age range',
                  value: '${_ageRange.start.round()} – ${_ageRange.end.round()}',
                ),
                const SizedBox(height: AppSpacing.xs),
                RangeSlider(
                  values: _ageRange,
                  min: 18,
                  max: 80,
                  divisions: 62,
                  onChanged: (value) => setState(() => _ageRange = value),
                ),
                const Divider(height: AppSpacing.md),
                const SizedBox(height: AppSpacing.xs),
                LabeledValue(
                  label: 'Maximum distance',
                  value: '${_maxDistanceKm.round()} km',
                ),
                const SizedBox(height: AppSpacing.xs),
                Slider(
                  value: _maxDistanceKm,
                  min: 1,
                  max: 200,
                  divisions: 199,
                  onChanged: (value) => setState(() => _maxDistanceKm = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
