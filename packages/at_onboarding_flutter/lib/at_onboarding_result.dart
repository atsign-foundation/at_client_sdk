/// The status of onboard's result
///
/// Values include: success, error, cancel
///
enum AtOnboardingResultStatus {
  success, //Authenticate success
  error, //Authenticate error
  cancel, //User canceled
}

enum AtOnboardingResetResult {
  cancelled,
  success,
}

/// The result returned after onboard
class AtOnboardingResult {
  /// Status of result
  AtOnboardingResultStatus status;

  /// The message returned when onboard failed
  String? message;

  /// The error code returned when onboard failed
  String? errorCode;

  /// The atSign returned when onboard successfully
  String? atsign;

  AtOnboardingResult._({
    required this.status,
    this.message,
    this.errorCode,
    this.atsign,
  });

  /// Create instance with success status
  ///
  /// [atsign] The name of atSign
  ///
  factory AtOnboardingResult.success({
    required String atsign,
  }) {
    return AtOnboardingResult._(
      status: AtOnboardingResultStatus.success,
      atsign: atsign,
    );
  }

  /// Create instance with error status
  ///
  /// [message] The message returned when onboard failed
  ///
  /// [errorCode] The error code returned when onboard failed
  ///
  factory AtOnboardingResult.error({
    String? message,
    String? errorCode,
  }) {
    return AtOnboardingResult._(
      status: AtOnboardingResultStatus.error,
      message: message,
      errorCode: errorCode,
    );
  }

  /// Create instance with cancel status
  factory AtOnboardingResult.cancelled() {
    return AtOnboardingResult._(
      status: AtOnboardingResultStatus.cancel,
    );
  }
}
