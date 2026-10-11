import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/ui_kit.dart';
import '../application/onboarding_state.dart';
import 'onboarding_progress.dart';

class BasicInfoStep extends StatefulWidget {
  const BasicInfoStep({super.key});

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit(OnboardingState state) {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    state.submitBasicInfo(displayName: name);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();
    final textTheme = Theme.of(context).textTheme;
    final hasName = _nameController.text.trim().isNotEmpty;
    return OnboardingScaffold(
      step: onboardingStepNumber(state.currentStep),
      totalSteps: kOnboardingStepCount,
      emoji: '👋',
      title: 'What should we call you?',
      subtitle: "This is how you'll appear to your matches. A first name or nickname works great.",
      errorMessage: state.errorMessage,
      primaryLabel: 'Continue',
      loading: state.isLoading,
      onPrimary: hasName ? () => _submit(state) : null,
      child: TextField(
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(state),
        style: textTheme.headlineSmall,
        decoration: const InputDecoration(
          labelText: 'Display name',
          hintText: 'e.g. Aanya',
        ),
      ),
    );
  }
}
