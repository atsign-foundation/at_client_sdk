import 'package:at_auth/src/keys/legacy/at_keys_legacy.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

// TODO: when doing at_auth 4.0.0, remove the AtChops, AtLookUp & AtKeys
// and ideally return an AtRootDomain instance on return as well. (UX)
sealed class AuthResponse {
  String atSign;
  bool isSuccessful = false;
  AtKeys? atAuthKeys;
  AtLookUp? atLookUp;
  AtChops? atChops;
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
