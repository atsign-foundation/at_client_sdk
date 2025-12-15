import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

/// Interface for onboarding and authentication to a secondary server of an atsign
abstract interface class AtAuth {
  AtChops? atChops;
  AtLookUp? atLookUp;
  Stream<ProgressEvent> get progressStream;

  factory AtAuth.create(
      {AtLookUp? atLookUp,
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

  /// Authenticate method is invoked when an atsign wants to authenticate to secondary server with an .atKeys file
  ///
  /// Step 1. Read the keys from AtKeysIo implementation
  /// - Can also be brought via AtAuthRequest.atAuthKeys
  ///
  /// Step 2  Perform pkam authentication
  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest);

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

  /// Validate atsign's secondary server status
  /// - Check if atsign's secondary server is reachable in atDirectory
  /// - AtOnboardingRequest: validates server for onboarding and looks for teapot
  /// - AtAuthRequest: validates server for authentication
  Future<void> validateAtServer(AuthRequest authRequest);
}
