import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

abstract class AtOnboardingService implements ProgressPublisher {
  static const Duration defaultApkamRetryInterval = Duration(seconds: 10);
  static const int defaultMaxApkamRetries = 5;

  static const Duration defaultActivationCheckInterval = Duration(seconds: 2);
  static const int defaultMaxActivationCheckRetries = 50;

  /// Perform initial one_time authentication to activate the atsign. Returns
  /// true if successfully onboarded.
  ///
  /// When [autoCompleteActivation] is false, callers are responsible for
  /// calling [completeActivation]
  Future<bool> onboard({
    bool autoCompleteActivation = true,
    Duration retryInterval = defaultActivationCheckInterval,
    int maxRetries = defaultMaxActivationCheckRetries,
  });

  /// - Update encryption public key to server
  ///
  /// - Delete cram secret from server
  Future<void> completeActivation();

  /// Authenticate into secondary server using PKAM privateKey for legacy clients
  ///
  /// For clients that are enrolled through APKAM, pass the enrollmentId and
  /// auth is done using APKAM private key
  ///
  /// Returns true if authentication is successful
  Future<bool> authenticate({String? enrollmentId});

  /// Sends an enroll request to the server, and waits for the request to be
  /// approved. Apps that are already enrolled will receive
  /// notifications for this enroll request and can approve/deny the request.
  ///
  /// If the request is denied, or times out, an exception will be thrown.
  ///
  /// This method internally calls [sendEnrollRequest], [awaitApproval], and
  /// [createAtKeysFile]. It supports resuming interrupted enrollments via a
  /// local checkpoint file; if a valid checkpoint is found, it skips the initial
  /// request and proceeds directly to [awaitApproval].
  ///
  /// [appName] - application name of the client e.g wavi,buzz, atmosphere etc.,
  ///
  /// [deviceName] - device identifier from the requesting application
  /// e.g iphone,any unique ID that identifies the requesting client
  ///
  /// [otp] - otp generated via an already enrolled app
  ///
  /// [namespaces] - key-value pair of namespace-access of the requesting client
  /// e.g {"wavi":"rw","contacts":"r"}
  ///
  /// [retryInterval] - how frequently to re-check if the request
  /// has been approved or denied.
  ///
  /// [atKeysFile] the file into which the atKeys generated for this enrollment
  /// will be written
  Future<AtEnrollmentResponse> enroll(
    String appName,
    String deviceName,
    String otp,
    Map<String, String> namespaces, {
    File? atKeysFile,
    Duration retryInterval = defaultApkamRetryInterval,
    int maxRetries = defaultMaxApkamRetries,
    Duration? apkamKeysExpiryDuration,
    /// The algorithm this enrollment's APKAM authentication keypair is minted
    /// under.
    ///
    /// **Defaulted here, and only here.** `AtEnrollmentRequest` requires it
    /// with no default, so that every caller states what it means rather than
    /// inheriting an algorithm it never chose. This is the boundary where a
    /// caller genuinely has none to state: an app calling `enroll` knows its
    /// appName and its namespaces, not the atSign's rollout position. RSA-2048
    /// is safe as that default because it is what this path minted
    /// unconditionally before the parameter existed, so an app that says
    /// nothing enrolls exactly as it always did.
    ///
    /// A deployment that HAS a position says so: pass
    /// `PqPosture.authenticationKeyAlgorithm`.
    SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  });

  /// Sends enrollment request. Application code may subsequently call
  /// [awaitApproval].
  Future<AtEnrollmentResponse> sendEnrollRequest(String appName,
      String deviceName, String otp, Map<String, String> namespaces,
      {Duration? apkamKeysExpiryDuration,
      /// See [enroll]'s `signingAlgo`: this is the same value on the
      /// send-then-await-separately path, defaulted the same way and for the
      /// same reason.
      SigningAlgoType signingAlgo = SigningAlgoType.rsa2048});

  /// Attempts PKAM auth until successful (i.e. request was approved).
  /// If the request was denied, an exception is thrown.
  ///
  /// The wait itself is not bounded — somebody has to decide this request, on
  /// their own schedule. [maxRetries] budgets consecutive failures to reach
  /// the atServer, the exit from an atServer that is genuinely gone; an
  /// answer from it restores the budget.
  ///
  /// Once successful, the full set of keys are available in
  /// [enrollmentResponse].atAuthKeys
  Future<void> awaitApproval(
    AtEnrollmentResponse enrollmentResponse, {
    Duration retryInterval = defaultApkamRetryInterval,
    bool logProgress = true,
    int maxRetries = defaultMaxApkamRetries,
  });

  /// Create a file in the standardized format which apps may use to
  /// authenticate to an atServer.
  Future<File> createAtKeysFile(
    AtEnrollmentResponse er, {
    File? atKeysFile,
    bool allowOverwrite = false,
  });

  /// Returns an authenticated instance of AtClient
  @Deprecated('use getter')
  Future<AtClient?> getAtClient();

  // return true if atsign is onboarded and keys are persisted in local storage. false otherwise
  Future<bool> isOnboarded();

  /// Returns authenticated instance of AtLookup
  @Deprecated('use getter')
  AtLookUp? getAtLookup();

  /// Closes the current instance of onboarding_service
  Future<void> close();

  set atClient(AtClient? atClient);

  AtClient? get atClient;

  set atLookUp(AtLookUp? atLookUp);

  AtLookUp? get atLookUp;

  set atChops(AtChops? atChops);

  AtChops? get atChops;

  set atAuth(AtAuth? atAuth);

  AtAuth? get atAuth;
}
