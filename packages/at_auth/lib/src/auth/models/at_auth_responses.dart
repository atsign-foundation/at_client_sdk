import 'package:at_auth/src/auth/models/at_auth_session.dart';

/// The result of activating an atSign.
///
/// [session] is the typed hand-off to the client, populated on success for a
/// request that carried an `AtKeysIo`.
sealed class AuthResponse {
  String atSign;
  bool isSuccessful = false;

  /// Explicit, typed hand-off to the client. Populated on success when the
  /// request supplied an `AtKeysIo`.
  AtAuthSession? session;

  /// The enrollment this activated as, from [session].
  String? get enrollmentId => session?.enrollmentId;

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
