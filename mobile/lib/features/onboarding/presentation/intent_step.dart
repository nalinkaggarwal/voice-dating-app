import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/onboarding_state.dart';

const _intentOptions = ['LONG_TERM', 'SHORT_TERM', 'NOT_SURE_YET'];

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
    return Scaffold(
      appBar: AppBar(title: const Text("What are you looking for?")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in _intentOptions)
              RadioListTile<String>(
                title: Text(option.replaceAll('_', ' ')),
                value: option,
                groupValue: _selected,
                onChanged: (value) => setState(() => _selected = value),
              ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.isLoading || _selected == null
                  ? null
                  : () => state.submitIntent(_selected!),
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
