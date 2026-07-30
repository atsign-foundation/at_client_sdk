import 'dart:async';

import 'package:at_auth/src/auth/models/at_auth_session.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

/// An abstract class for submitting and managing the enrollment requests.
abstract class AtEnrollment {
  factory AtEnrollment.create() {
    return AtEnrollmentImpl();
  }

  Stream<ProgressEvent> get progressStream;

  /// Submits an app's enrollment request, generating an APKAM key-pair with
  /// access limited to the namespaces the request asks for.
  ///
  /// The [AtEnrollmentRequest] accepts an [AtAuthSession] (the source of the atsign, rootDomain and the
  /// atKeysIo the new keys are persisted into) plus the enrollment-specific appName, deviceName, namespaces and otp.
  ///
  /// The [atLookUp] parameter is used to perform lookups to secondary server to submit an enrollment request.
  ///
  /// Returns the [PendingEnrollment] the server created: its id and status, the
  /// session it belongs to, and the APKAM keys minted here. Hand it straight to
  /// [waitForApproval], which needs those keys to finish the handshake.
  ///
  /// ```dart
  ///   AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
  ///                     session: session, // atsign + rootDomain + atKeysIo destination
  ///                     appName: 'wavi',
  ///                     deviceName: 'my-device',
  ///                     namespaces: {'wavi': 'rw'},
  ///                     otp: '123');
  ///
  ///     PendingEnrollment pending =
  ///         await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
  ///     await atEnrollmentBase.waitForApproval(pending);
  ///     // pending.session -> AtClientManager.fromAuthSession(...)
  ///```
  ///
  /// To submit the *first* enrollment for an atsign, use [submitFirstEnrollment].
  Future<PendingEnrollment> submit(
      AtEnrollmentRequest enrollmentRequest, AtLookUp atLookUp);

  /// Submits the first enrollment for an atsign — the one onboarding (activating)
  /// it sends over its CRAM authenticated connection.
  ///
  /// The server assigns the "__manage" namespace, which has access to all namespaces and serves as the administrator app
  /// responsible for approving subsequent enrollment requests.
  ///
  /// The enrollment request is auto-approved. When an @ sign is initially onboarded and the enableEnrollment flag is set to
  /// true in AtClientPreferences, the enrollment is sent to the server. In this scenario, because there's no app available for
  /// approval yet, the initial enrollment (submitted over a CRAM authenticated connection) is automatically approved.
  /// Conversely, if enableEnrollment is set to false, the enrollment isn't submitted, which means subsequent enrollment requests
  /// cannot be approved by the app.
  ///
  /// Unlike [submit] this mints no keys: onboarding generates the keyset
  /// (`AtKeys.generate`) and passes only [FirstEnrollmentRequest.apkamPublicKey].
  /// The response therefore carries no keys either — just the enrollmentId and
  /// status, which the caller checks is [EnrollmentStatus.approved].
  ///
  /// ```dart
  ///   FirstEnrollmentRequest firstEnrollmentRequest = FirstEnrollmentRequest(
  ///       session: session,
  ///       appName: 'wavi',
  ///       deviceName: 'iphone',
  ///       apkamPublicKey: atKeys.apkamPublicKey!.toString());
  ///
  ///   AtEnrollmentResponse response = await atEnrollmentBase
  ///       .submitFirstEnrollment(firstEnrollmentRequest, atLookUp);
  ///```
  Future<AtEnrollmentResponse> submitFirstEnrollment(
      FirstEnrollmentRequest enrollmentRequest, AtLookUp atLookUp);

  /// Approves an enrollment request.
  ///
  /// Takes an [EnrollmentApproval] — build it with
  /// [EnrollmentRequestDecision.approved] from the enrollmentId and
  /// encryptedApkamSymmetricKey the atServer notified, or from the
  /// [ServerEnrollmentRequest] that [list] returned.
  ///
  /// Upon approval, the encryptedApkamSymmetricKey is decrypted with the
  /// approver's default encryption *private* key to retrieve the original APKAM
  /// symmetric key. The default encryption private key and the self-encryption key
  /// are then encrypted under that symmetric key and transmitted to the atServer
  /// for the requesting app.
  ///
  /// The [atLookUp] parameter is used to perform lookups during approval management.
  ///
  /// [session] is the *approving* app's own session — the source of the atsign
  /// being administered. Approval needs the approver's encryption private key and
  /// self encryption key, to re-encrypt them for the new enrollment; those are
  /// read from [AtAuthSession.atKeysIo].
  ///
  /// Returns a [Future] containing an [AtEnrollmentResponse] representing the result of the approval.
  ///
  /// ```dart
  /// AtEnrollment atEnrollment = AtEnrollment.create();
  ///
  /// AtEnrollmentResponse atEnrollmentResponse = await atEnrollment.approve(
  ///     EnrollmentRequestDecision.approved(
  ///       enrollmentId: request.enrollmentId,
  ///       encryptedApkamSymmetricKey: request.encryptedAPKAMSymmetricKey!,
  ///     ),
  ///     atLookUp,
  ///     mySession);
  /// ```
  Future<AtEnrollmentResponse> approve(
    EnrollmentApproval approval,
    AtAuthSession session,
  );

  /// Denies an enrollment request, preventing the requesting app from
  /// authenticating to the atServer.
  ///
  /// Takes an [EnrollmentDenial] — build it with
  /// [EnrollmentRequestDecision.denied].
  /// The [atLookUp] parameter is used to perform lookups during approval management.
  ///
  /// [session] is the approving app's own session; denial needs no keys from it,
  /// but the returned response is scoped to it.
  ///
  /// Returns a [Future] containing an [AtEnrollmentResponse] representing the result of the denial.
  ///
  /// ```dart
  /// AtEnrollment atEnrollment = AtEnrollment.create();
  ///
  /// AtEnrollmentResponse atEnrollmentResponse = await atEnrollment.deny(
  ///     EnrollmentRequestDecision.denied('dummy-enrollment-id'),
  ///     atLookUp,
  ///     mySession);
  /// ```
  Future<AtEnrollmentResponse> deny(
    EnrollmentDenial denial,
    AtAuthSession session,
  );

  /// Revokes an approved enrollment, closing any active connections and making it inactive for future use.
  ///
  /// Takes an [EnrollmentRevocation] — build it with
  /// [EnrollmentRequestDecision.revoked]. Pass `force: true` there to revoke the
  /// enrollment the current client is itself authenticated under.
  /// The [atLookUp] parameter is used to perform lookups during approval management.
  ///
  /// [session] is the approving app's own session, as for [deny].
  ///
  /// Returns a [Future] containing an [AtEnrollmentResponse] representing the result of the revoke.
  ///
  /// ```dart
  /// AtEnrollment atEnrollment = AtEnrollment.create();
  ///
  /// AtEnrollmentResponse atEnrollmentResponse = await atEnrollment.revoke(
  ///     EnrollmentRequestDecision.revoked('dummy-enrollment-id'),
  ///     atLookUp,
  ///     mySession);
  /// ```
  Future<AtEnrollmentResponse> revoke(
    EnrollmentRevocation revocation,
    AtAuthSession session,
  );

  /// Lists all enrollments.
  ///
  /// Accepts [EnrollmentStatus] inside the [statusFilters] parameter to filter enrollments with their current status.
  ///
  /// Returns a [Future] containing a [List<EnrollmentServerRequest>] representing all the enrollments.
  Future<List<ServerEnrollmentRequest>> list(
      List<EnrollmentStatus>? statusFilters, AtLookUp atLookUp,
      {String? arx, String? drx});

  /// Generates a one-time passcode from the server.
  ///
  /// [expiry] defaults to 5 minutes.
  Future<Otp> generateOtp(AtLookUp atLookUp,
      {Duration expiry = const Duration(minutes: 5)});

  /// Sets a semi-permanent passcode on the server.
  ///
  /// [spp] must be alphanumeric and exactly 6 characters.
  /// [expiry] defaults to 5 minutes.
  Future<Otp> setSpp(String spp, AtLookUp atLookUp,
      {Duration expiry = const Duration(minutes: 5)});

  ///Awaits for approval/deny of an enrollment request at regular intervals.
  /// The polling continues until a final status is received or the maximum number of retries is reached.
  ///The [logProgress] parameter, when set to true, enables logging of the progress during the polling process.
  /// The [maxRetries] parameter specifies the maximum number of polling attempts before giving up.
  /// The [retryInterval] parameter defines the duration to wait between each polling attempt.
  ///
  /// ```dart
  /// AtEnrollment atEnrollment = AtEnrollment.create();
  ///
  /// final pending = await atEnrollment.submit(enrollmentRequest, atLookUp);
  ///
  /// try {
  ///   await atEnrollment.waitForApproval(pending);
  ///   // pending.session is now authenticated and its keys are persisted.
  ///   AtClientManager.fromAuthSession(pending.session);
  /// } catch (e) {
  ///   // Handle errors
  /// }
  /// ```
  ///
  /// Takes the [PendingEnrollment] returned by [submit] — it carries both the
  /// session to persist into and the APKAM keys minted at submit time, which
  /// this call completes with the material fetched from the atServer.
  ///
  /// On success a fully qualified `AtEnrollmentResponse` is created.
  Future<AtEnrollmentResponse> waitForApproval(
    PendingEnrollment pending, {
    bool logProgress = false,
    int maxRetries = 48,
    Duration retryInterval = const Duration(minutes: 1),
  });
}
