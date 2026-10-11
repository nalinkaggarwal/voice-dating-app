import '../domain/onboarding_step.dart';

/// Steps shown in the progress bar ("Step n of N") -- everything before
/// [OnboardingStep.complete], which is the celebration, not a step.
const int kOnboardingStepCount = 6;

/// 1-based position of [step] in the progress bar.
int onboardingStepNumber(OnboardingStep step) =>
    (step.index + 1).clamp(1, kOnboardingStepCount);
