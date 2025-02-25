/// The status of the onboarding result
enum AtOnboardingResultStatus {
  /// Authenticate success
  success,

  /// Authenticate error
  error,

  /// User cancelled
  cancelled,
}

/// The result returned after onboarding
class AtOnboardingResult {
  /// Create instance with success status.
  ///
  /// [atsign] The name of atSign.
  const AtOnboardingResult.success({
    required this.atsign,
  })  : errorMessage = null,
        errorCode = null;

  /// Create instance with error status
  ///
  /// [message] The message returned when onboard failed
  ///
  /// [errorCode] The error code returned when onboard failed
  const AtOnboardingResult.error({
    required this.errorMessage,
    required this.errorCode,
  }) : atsign = null;

  /// Create instance with cancel status
  const AtOnboardingResult.cancelled()
      : atsign = null,
        errorCode = null,
        errorMessage = null;

  /// The atSign returned when onboard successfully.
  final String? atsign;

  /// The message returned when onboard failed.
  final String? errorMessage;

  /// The error code returned when onboard failed.
  final String? errorCode;

  /// The status of the onboarding result.
  AtOnboardingResultStatus getStatus() {
    if (errorMessage != null || errorCode != null) {
      return AtOnboardingResultStatus.error;
    } else if (atsign != null) {
      return AtOnboardingResultStatus.success;
    } else {
      return AtOnboardingResultStatus.cancelled;
    }
  }
}
