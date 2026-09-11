import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

/// The result of onboarding or authenticating an atSign.
///
/// [session] is the typed hand-off to the client, and supersedes the
/// deprecated [atAuthKeys], [atLookUp] and [atChops] fields. It is populated
/// on success for every request that carried an [AtKeysIo] — which is every
/// request that did not hand over a fixed key set instead.
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

  /// The enrollment this authenticated as.
  ///
  /// From [session] where there is one, which is every request carrying an
  /// [AtKeysIo]; from the deprecated keys otherwise, so a caller that passed
  /// a fixed key set still gets an answer.
  String? get enrollmentId =>
      // ignore: deprecated_member_use_from_same_package
      session?.enrollmentId ?? atAuthKeys?.enrollmentId;

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

/// Represents an authentication response of an atSign.
class AtAuthResponse extends AuthResponse {
  /// Constructor that takes an @sign as a parameter
  AtAuthResponse(super.atSign);

  @override
  String toString() {
    return 'AtAuthResponse{atSign: $atSign, isSuccessful: $isSuccessful}';
  }
}
