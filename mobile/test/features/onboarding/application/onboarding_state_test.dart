import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/features/onboarding/application/onboarding_state.dart';
import 'package:lolly/features/onboarding/domain/onboarding_step.dart';
import 'package:lolly/shared/models/user.dart';

void main() {
  group('OnboardingState.resumeFrom', () {
    late OnboardingState state;

    setUp(() {
      state = OnboardingState();
    });

    test('maps every UserStatus to a sensible resume step', () {
      const expected = {
        UserStatus.accountCreated: OnboardingStep.basicInfo,
        UserStatus.basicInfoDone: OnboardingStep.preferences,
        UserStatus.preferencesDone: OnboardingStep.intent,
        UserStatus.intentDone: OnboardingStep.voiceRecording,
        UserStatus.voiceRecorded: OnboardingStep.voiceRecording,
        UserStatus.aiReviewDone: OnboardingStep.photo,
        UserStatus.photoUploaded: OnboardingStep.complete,
        UserStatus.active: OnboardingStep.complete,
      };

      for (final entry in expected.entries) {
        state.resumeFrom(entry.key);
        expect(state.currentStep, entry.value, reason: 'failed for ${entry.key}');
      }
    });

    test('a fully active user lands on the complete step, not basicInfo', () {
      state.resumeFrom(UserStatus.active);
      expect(state.currentStep, OnboardingStep.complete);
    });
  });
}
