import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

sealed class AuthResponse {
  String atSign;
  bool isSuccessful = false;
  //todo: v4, please return a AtRootDomain, helps cleanup the sdk.
  //will remain the response
  AtKeys? atAuthKeys;
  @Deprecated('remove in v4')
  AtLookUp? atLookUp;
  @Deprecated('remove in v4')
  AtChops? atChops;
  // todo: only functional for old-style keys... needs rethinking.
  String? get enrollmentId => atAuthKeys?.enrollmentId;

  AuthResponse(this.atSign);
}

/// Represents an onboarding response of an atSign.
class AtOnboardingResponse extends AuthResponse {
  /// Constructor for [AtOnboardingResponse]
  /// [atSign] is the atSign for onboarding
  AtOnboardingResponse(super.atSign);

  @override
  String toString() {
    return 'AtOnboardingResponse{atSign: $atSign, enrollmentId: $enrollmentId, isSuccessful: $isSuccessful}';
  }
}

class AtAuthResponse extends AuthResponse {
  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(super.atSign);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
