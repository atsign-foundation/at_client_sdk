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
  /// If the request is denied, or times out, an exception will be thrown.
  ///
  /// Calling this method is exactly equivalent to calling
  /// [sendEnrollRequest], [awaitApproval] and [createAtKeysFile] in turn.
  ///
  /// [appName] - application name of the client e.g wavi,buzz, atmosphere etc.,
  /// [deviceName] - device identifier from the requesting application e.g iphone,any unique ID that identifies the requesting client
  /// [otp] - otp generated via an already enrolled app
  /// [namespaces] - key-value pair of namespace-access of the requesting client e.g {"wavi":"rw","contacts":"r"}
  /// [retryInterval] - how frequently to re-check if the request
  /// has been approved or denied.
  Future<AtEnrollmentResponse> enroll(
    String appName,
    String deviceName,
    String otp,
    Map<String, String> namespaces, {
    File? atKeysFile,
    Duration retryInterval = defaultApkamRetryInterval,
    int maxRetries = defaultMaxApkamRetries,
  });

  /// Sends enrollment request. Application code may subsequently call
  /// [awaitApproval].
  Future<AtEnrollmentResponse> sendEnrollRequest(String appName,
      String deviceName, String otp, Map<String, String> namespaces,
      {Duration? apkamKeysExpiryDuration});

  /// Attempts PKAM auth until successful (i.e. request was approved).
  /// If the request was denied, or times out, then an exception is thrown.
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
