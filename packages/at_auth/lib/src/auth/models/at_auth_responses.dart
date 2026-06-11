import 'package:at_commons/at_commons.dart';

/// Generic response class for all types of authentication methods
/// Suggest you use this type for methods where all types of Responses are available.
sealed class AuthResponse {
  String atSign;
  AtRootDomain rootDomain;
  bool isSuccessful = false;
  AtKeysSet atKeysSet;
  String? get enrollmentId => atKeysSet.enrollmentId;

  AuthResponse(this.atSign, this.rootDomain, this.atKeysSet);
}

/// Represents an onboarding response of an atSign.
class AtOnboardingResponse extends AuthResponse {
  /// Constructor for [AtOnboardingResponse]
  /// [atSign] is the atSign for onboarding
  AtOnboardingResponse(super.atSign, super.rootDomain, super.atKeysSet);

  @override
  String toString() {
    return 'AtOnboardingResponse{atSign: $atSign, enrollmentId: $enrollmentId, isSuccessful: $isSuccessful}';
  }
}

class AtAuthResponse extends AuthResponse {
  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(super.atSign, super.rootDomain, super.atKeysSet);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
