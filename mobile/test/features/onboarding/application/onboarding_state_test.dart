import 'package:flutter_test/flutter_test.dart';
import 'package:lolly/features/onboarding/application/onboarding_state.dart';
import 'package:lolly/features/onboarding/data/onboarding_repository.dart';
import 'package:lolly/features/onboarding/domain/onboarding_step.dart';
import 'package:lolly/features/onboarding/domain/voice_answer.dart';
import 'package:lolly/shared/models/user.dart';

/// A real OnboardingRepository talks to the network (ApiClient) -- fine for
/// the pure-synchronous status->step mapping below, but resumeFrom's
/// VOICE_RECORDED path now calls getLatestVoiceAnswer() for real, so those
/// cases need a fake that doesn't touch the network.
class _FakeRepository extends OnboardingRepository {
  _FakeRepository({this.latestVoiceAnswer, this.latestVoiceAnswerError});

  final VoiceAnswer? latestVoiceAnswer;
  final Object? latestVoiceAnswerError;

  @override
  Future<VoiceAnswer> getLatestVoiceAnswer() async {
    if (latestVoiceAnswerError != null) throw latestVoiceAnswerError!;
    return latestVoiceAnswer!;
  }
}

void main() {
  group('OnboardingState.resumeFrom', () {
    late OnboardingState state;

    setUp(() {
      state = OnboardingState(repository: _FakeRepository(latestVoiceAnswerError: 'unused in this group'));
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

  group('OnboardingState.resumeFrom VOICE_RECORDED upgrade', () {
    test('upgrades from voiceRecording to aiReview once the latest voice answer is found', () async {
      const answer = VoiceAnswer(id: 'va-1', status: VoiceAnswerStatus.draftReady, claims: []);
      final state = OnboardingState(repository: _FakeRepository(latestVoiceAnswer: answer));

      state.resumeFrom(UserStatus.voiceRecorded);
      expect(state.currentStep, OnboardingStep.voiceRecording, reason: 'safe synchronous default');

      await Future<void>.delayed(Duration.zero);
      expect(state.currentStep, OnboardingStep.aiReview);
      expect(state.voiceAnswer, same(answer));
    });

    test('stays on voiceRecording if no voice answer can be found', () async {
      final state = OnboardingState(repository: _FakeRepository(latestVoiceAnswerError: Exception('404')));

      state.resumeFrom(UserStatus.voiceRecorded);
      await Future<void>.delayed(Duration.zero);

      expect(state.currentStep, OnboardingStep.voiceRecording);
      expect(state.voiceAnswer, isNull);
    });
  });
}
