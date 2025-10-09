import 'package:at_auth/src/keys/at_keys.dart';

sealed class AtResponse {
  String atSign;
  bool isSuccessful = false;
  AtKeys? atAuthKeys;

  AtResponse(this.atSign);
}

/// Represents an onboarding response of an atSign.
class AtOnboardingResponse extends AtResponse {
  String? enrollmentId;

  /// Constructor for [AtOnboardingResponse]
  /// [atSign] is the atSign for onboarding
  /// 
  AtOnboardingResponse(super.atSign);

  @override
  String toString() {
    return 'AtOnboardingResponse{atSign: $atSign, enrollmentId: $enrollmentId, isSuccessful: $isSuccessful}';
  }
}

class AtAuthResponse extends AtResponse {
  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(super.atSign);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
