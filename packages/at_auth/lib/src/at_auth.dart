import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

/// The activation engine `activateAtSign` drives: CRAM authentication, key
/// minting and the first enrollment. Logging in is at_client's `Atsign.open`.
abstract interface class AtAuth {
  /// The connection every step of the activation travels over.
  AtLookupMuxable get atLookUp;
  Stream<ProgressEvent> get progressStream;

  factory AtAuth.create(
      {required AtLookupMuxable atLookUp,
      AtChops? atChops,
      CramAuthenticator? cramAuthenticator,
      PkamAuthenticator? pkamAuthenticator,
      AtEnrollment? atEnrollmentBase}) {
    return AtAuthImpl(
        atLookUp: atLookUp,
        atChops: atChops,
        cramAuthenticator: cramAuthenticator,
        pkamAuthenticator: pkamAuthenticator,
        atEnrollment: atEnrollmentBase);
  }

  /// Onboard method is invoked when an atsign is activated for the first time from a client app.
  /// - Connect, and perform cram auth
  /// - Generate pkam, encryption keypairs and apkam symmetric key
  /// - Update pkam public key to secondary
  /// - Close connection
  /// - Reconnect, and perform pkam auth
  /// - If required (legacy behaviour, but not recommended), then call
  /// [completeActivation]
  /// <p/>
  ///
  /// Set [atOnboardingRequest.publicKeyId] if pkam auth mode is [PkamAuthMode.sim]
  Future<AtOnboardingResponse> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret, {
    bool autoCompleteActivation = true,
  });

  /// - Update encryption public key to server
  /// - Delete cram secret from server
  Future<void> completeActivation();

  /// Waits, over [atLookUp], until the atDirectory knows the atSign and its
  /// atServer answers; for onboarding, the atSign must also not be activated.
  Future<void> validateAtServer(AuthRequest authRequest);
}
