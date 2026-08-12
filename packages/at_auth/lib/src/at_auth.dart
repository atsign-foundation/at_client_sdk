import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

/// Probes whether the atServer at ([host], [port]) is listening yet, completing
/// normally when it is and throwing when it is not.
///
/// [validateAtServer] polls this while waiting for a newly-provisioned atServer
/// to come up. The transport is the caller's choice: the WASM-safe barrel ships
/// no default, and `package:at_auth/at_auth_io.dart` supplies the TLS-socket
/// implementation (`secureSocketProbe`) this package used before 4.0.0.
typedef AtServerProbe = Future<void> Function(String host, int port);

/// Interface for onboarding and authentication to a secondary server of an atsign
abstract interface class AtAuth {
  AtChops? atChops;
  AtLookUp? atLookUp;
  Stream<ProgressEvent> get progressStream;

  /// Leaving [probeSocket] null skips the atServer readiness probe in
  /// [validateAtServer]. On a `dart:io` host, pass `secureSocketProbe` from
  /// `package:at_auth/at_auth_io.dart` to get the pre-4.0.0 behaviour.
  factory AtAuth.create(
      {AtLookUp? atLookUp,
      AtChops? atChops,
      CramAuthenticator? cramAuthenticator,
      PkamAuthenticator? pkamAuthenticator,
      AtEnrollment? atEnrollmentBase,
      AtServerProbe? probeSocket}) {
    return AtAuthImpl(
        atLookUp: atLookUp,
        atChops: atChops,
        cramAuthenticator: cramAuthenticator,
        pkamAuthenticator: pkamAuthenticator,
        atEnrollment: atEnrollmentBase,
        probeSocket: probeSocket);
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
