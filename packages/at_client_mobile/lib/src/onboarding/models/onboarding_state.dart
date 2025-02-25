/// Top level state of the onboarding process.
enum OnboardingState {
  /// Initial state of onboarding.
  unauthenticated,

  /// Onboarding a new atSign.
  registering,

  /// Authenticating with the atServer.
  authenticating,

  /// Error state.
  error,
}
