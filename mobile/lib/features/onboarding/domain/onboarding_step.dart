/// Mirrors the onboarding progression in the WP2 brief. Not a 1:1 mirror
/// of backend UserStatus (that enum also includes ACCOUNT_CREATED/ACTIVE,
/// which aren't "a step to show a screen for" on the client) -- this is
/// the client-side view of "which screen do I show right now".
enum OnboardingStep {
  basicInfo,
  preferences,
  intent,
  voiceRecording,
  aiReview,
  photo,
  complete,
}
