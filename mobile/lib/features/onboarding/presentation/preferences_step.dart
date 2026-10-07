import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/onboarding_state.dart';

const _genderOptions = ['MEN', 'WOMEN', 'NON_BINARY'];

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
    return Scaffold(
      appBar: AppBar(title: const Text('Who are you interested in?')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: _genderOptions.map((g) {
                final selected = _selectedGenders.contains(g);
                return FilterChip(
                  label: Text(g.replaceAll('_', ' ')),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    value ? _selectedGenders.add(g) : _selectedGenders.remove(g);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('Age range: ${_ageRange.start.round()} - ${_ageRange.end.round()}'),
            RangeSlider(
              values: _ageRange,
              min: 18,
              max: 80,
              divisions: 62,
              onChanged: (value) => setState(() => _ageRange = value),
            ),
            const SizedBox(height: 16),
            Text('Max distance: ${_maxDistanceKm.round()} km'),
            Slider(
              value: _maxDistanceKm,
              min: 1,
              max: 200,
              divisions: 199,
              onChanged: (value) => setState(() => _maxDistanceKm = value),
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(state.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.isLoading || _selectedGenders.isEmpty
                  ? null
                  : () => state.submitPreferences(
                        genderInterest: _selectedGenders.toList(),
                        ageMin: _ageRange.start.round(),
                        ageMax: _ageRange.end.round(),
                        maxDistanceKm: _maxDistanceKm.round(),
                      ),
              child: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
