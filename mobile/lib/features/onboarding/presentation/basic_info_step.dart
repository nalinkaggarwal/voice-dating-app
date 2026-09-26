import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/onboarding_state.dart';

class BasicInfoStep extends StatefulWidget {
  const BasicInfoStep({super.key});

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tell us about you')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.isLoading
                  ? null
                  : () {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) return;
                      state.submitBasicInfo(displayName: name);
                    },
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
