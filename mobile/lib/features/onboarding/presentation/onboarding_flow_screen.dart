import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/user.dart';
import '../application/onboarding_state.dart';
import '../domain/onboarding_step.dart';
import 'basic_info_step.dart';
import 'claims_review_step.dart';
import 'intent_step.dart';
import 'onboarding_complete_step.dart';
import 'photo_upload_step.dart';
import 'preferences_step.dart';
import 'voice_recording_step.dart';

/// Top-level coordinator for the WP2 onboarding flow -- swaps the visible
/// step screen based on OnboardingState.currentStep. No named routes /
/// back-navigation between steps by design (matches the linear
/// basic-info -> ... -> photo flow in the brief); a user can't skip
/// ahead because each step's completion is what advances currentStep.
class OnboardingFlowScreen extends StatelessWidget {
  const OnboardingFlowScreen({super.key, this.resumeFrom, required this.currentUserId});

  /// The user's current backend UserStatus, so a returning user resumes
  /// at the right step instead of restarting at basicInfo.
  final UserStatus? resumeFrom;

  /// Only actually needed once OnboardingCompleteStep hands off to
  /// DiscoveryHomeScreen (WP5's messaging needs it there) -- threaded
  /// through the whole switcher anyway since main.dart already has it on
  /// hand from the same User fetch resumeFrom comes from.
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final state = OnboardingState();
        if (resumeFrom != null) state.resumeFrom(resumeFrom!);
        return state;
      },
      child: _OnboardingStepSwitcher(currentUserId: currentUserId),
    );
  }
}

class _OnboardingStepSwitcher extends StatelessWidget {
  const _OnboardingStepSwitcher({required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final step = context.watch<OnboardingState>().currentStep;
    switch (step) {
      case OnboardingStep.basicInfo:
        return const BasicInfoStep();
      case OnboardingStep.preferences:
        return const PreferencesStep();
      case OnboardingStep.intent:
        return const IntentStep();
      case OnboardingStep.voiceRecording:
        return const VoiceRecordingStep();
      case OnboardingStep.aiReview:
        return const ClaimsReviewStep();
      case OnboardingStep.photo:
        return const PhotoUploadStep();
      case OnboardingStep.complete:
        return OnboardingCompleteStep(currentUserId: currentUserId);
    }
  }
}
