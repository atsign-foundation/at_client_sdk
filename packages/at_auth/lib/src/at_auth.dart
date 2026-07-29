import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

import 'auth/models/at_auth_session.dart';

/// Interface for onboarding and authentication to a secondary server of an atsign
abstract interface class AtAuth {
  AtLookUp? atLookUp;
  Stream<ProgressEvent> get progressStream;

  /// [probeSocket] verifies the atServer is reachable before onboarding or
  /// authenticating, in [validateAtServer]. Opening a socket is `dart:io`, so
  /// the wasm-safe core has no implementation of its own — VM and Flutter
  /// callers should pass `defaultProbeSocket` from `at_auth_io.dart`:
  ///
  /// ```dart
  /// AtAuth.create(probeSocket: defaultProbeSocket);
  /// ```
  ///
  /// Left null, the reachability probe is skipped (the atDirectory lookup still
  /// runs, so an unreachable atServer surfaces later, from the connection
  /// attempt rather than from validation).
  factory AtAuth.create(
      {AtLookUp? atLookUp,
      CramAuthenticator? cramAuthenticator,
      PkamAuthenticator? pkamAuthenticator,
      Future<void> Function(String host, int port)? probeSocket,
      AtEnrollment? atEnrollmentBase}) {
    return AtAuthImpl(
        atLookUp: atLookUp,
        cramAuthenticator: cramAuthenticator,
        pkamAuthenticator: pkamAuthenticator,
        probeSocket: probeSocket,
        atEnrollment: atEnrollmentBase);
  }

  /// Authenticates an atsign to its atServer with PKAM.
  ///
  /// Step 1. Read the keys from the request's [AtKeysIo] — that is the only
  /// way keys enter authentication.
  ///
  /// Step 2. Perform pkam authentication.
  ///
  /// Returns the [AtAuthSession] to hand to client creation. Failure throws
  /// [AtAuthenticationException]; there is no unsuccessful return value.
  Future<AtAuthSession> authenticate(AtAuthRequest atAuthRequest);

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
  Future<AtAuthSession> onboard(
    AtOnboardingRequest atOnboardingRequest,
    String cramSecret, {
    bool autoCompleteActivation = true,
  });

  /// - Update encryption public key to server
  /// - Delete cram secret from server
  Future<void> completeActivation(AtAuthSession incompleteSession);

  /// Validate atsign's secondary server status
  /// - Check if atsign's secondary server is reachable in atDirectory
  /// - AtOnboardingRequest: validates server for onboarding and looks for teapot
  /// - AtAuthRequest: validates server for authentication
  Future<void> validateAtServer(AuthRequest authRequest);
}
