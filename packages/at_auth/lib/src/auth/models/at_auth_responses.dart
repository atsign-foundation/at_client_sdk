import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

@Deprecated('remove in v5 in favour of AtAuthSession')
sealed class AuthResponse {
  String atSign;
  bool isSuccessful = false;
  //todo: v5, please return a AtRootDomain, helps cleanup the sdk.
  @Deprecated('remove in v5')
  AtKeys? atAuthKeys;
  @Deprecated('remove in v5')
  AtLookUp? atLookUp;
  @Deprecated('remove in v5')
  AtChops? atChops;

  /// Explicit, typed hand-off to the client. Populated on success when the
  /// request supplied an [AtKeysIo]. The forward-looking replacement for the
  /// deprecated [atLookUp]/[atChops] fields.
  AtAuthSession? session;

  // todo: only functional for old-style keys... needs rethinking.
  String? get enrollmentId => atAuthKeys?.enrollmentId;

  AuthResponse(this.atSign);
}

@Deprecated('remove in v5 in favour of AtAuthSession')

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

@Deprecated('remove in v5 in favour of AtAuthSession')
class AtAuthResponse extends AuthResponse {
  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(super.atSign);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
