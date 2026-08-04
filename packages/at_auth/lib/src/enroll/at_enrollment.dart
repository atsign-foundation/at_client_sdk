import 'dart:async';

import 'package:at_auth/src/auth/apkam_signing.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_request.dart';
import 'package:at_auth/src/enroll/models/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/models/enrollment_request_decision.dart';
import 'package:at_auth/src/enroll/models/otp.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

import '../keys/io/at_keys_io.dart';

/// An abstract class for submitting and managing the enrollment requests.
abstract class AtEnrollment {
  /// How long [waitForApproval] waits between PKAM attempts, and how many it
  /// makes before giving up. Declared here so the interface and the
  /// implementation cannot drift — Dart resolves a default from the static
  /// receiver type, so two sets of values would mean the wait depends on how
  /// the variable was declared.
  static const Duration defaultRetryInterval = Duration(seconds: 2);
  static const int defaultMaxRetries = 15;

  /// The connection enrollment operations run over — the caller's, already
  /// authenticated.
  AtLookUp get atLookUp;

  /// The APKAM signing scheme [waitForApproval] authenticates the new
  /// enrollment with. The caller's choice, not inferred from key material.
  ApkamSigning get signing;

  factory AtEnrollment.create(AtLookUp lookUp,
      {ApkamSigning signing = ApkamSigning.legacy}) {
    return AtEnrollmentImpl(lookUp, signing: signing);
  }

  Stream<ProgressEvent> get progressStream;

  /// Submits an enrollment request over [atLookUp].
  ///
  /// [FirstEnrollmentRequest] is the activation case, submitted over a
  /// CRAM-authenticated connection. Because no app exists yet to approve it, the
  /// atServer auto-approves it and grants the `__manage` namespace, making it
  /// the administrator enrollment that approves every later request. `AtAuth`
  /// sends this one itself during [AtAuth.onboard].
  ///
  /// [AtEnrollmentRequest] is every subsequent request: it mints an APKAM
  /// keypair scoped to the namespaces it asks for, and returns a
  /// [PendingEnrollment] the caller hands to [waitForApproval]. Access is
  /// limited to those namespaces once an administrator app approves it.
  ///
  /// See `example/enrollment_request.dart` for the full flow.
  Future<AtEnrollmentResponse> enroll(EnrollmentRequest enrollmentRequest);

  /// Approves an enrollment request.
  ///
  /// The `enrollmentId` and its `encryptedAPKAMSymmetricKey` arrive in the
  /// notification of the request and go in via
  /// [EnrollmentRequestDecision.approved].
  ///
  /// [atsign] and [atKeysIo] identify the *approving* app and supply its own key
  /// material: the encryption private key decrypts the enrollee's APKAM
  /// symmetric key, then that key re-encrypts the approver's encryption private
  /// key and self-encryption key for the atServer to hold until the new
  /// enrollment collects them.
  Future<AtEnrollmentResponse> approve(
    Atsign atsign,
    AtKeysIo atKeysIo,
    EnrollmentRequestDecision enrollmentRequestDecision,
  );

  /// Denies an enrollment request, over [atLookUp].
  ///
  /// Unlike [approve], denial needs no key material — build the decision with
  /// [EnrollmentRequestDecision.denied].
  Future<AtEnrollmentResponse> deny(
    EnrollmentRequestDecision enrollmentRequestDecision,
  );

  /// Revokes an approved enrollment over [atLookUp], closing its active
  /// connections and making it unusable.
  ///
  /// Build the decision with [EnrollmentRequestDecision.revoked]; as for [deny],
  /// no key material is needed.
  Future<AtEnrollmentResponse> revoke(
    EnrollmentRequestDecision enrollmentRequestDecision,
  );

  /// Lists all enrollments.
  ///
  /// Accepts [EnrollmentStatus] inside the [statusFilters] parameter to filter enrollments with their current status.
  ///
  /// Returns a [Future] containing a [List<EnrollmentServerRequest>] representing all the enrollments.
  Future<List<ServerEnrollmentRequest>> list(
    List<EnrollmentStatus>? statusFilters, {
    String? arx,
    String? drx,
  });

  /// Generates a one-time passcode from the server.
  ///
  /// [expiry] defaults to 5 minutes.
  Future<Otp> generateOtp({Duration expiry = const Duration(minutes: 5)});

  /// Sets a semi-permanent passcode on the server.
  ///
  /// [spp] must be alphanumeric and exactly 6 characters.
  /// [expiry] defaults to 5 minutes.
  Future<Otp> setSpp(
    String spp, {
    Duration expiry = const Duration(minutes: 5),
  });

  /// Polls until the atServer approves or denies [pending], retrying PKAM every
  /// [retryInterval] for at most [maxRetries] attempts. [logProgress] emits each
  /// attempt on [progressStream].
  ///
  /// Takes the [PendingEnrollment] returned by [enroll], whose APKAM keys were
  /// minted at submit time but are not yet complete — approval is what releases
  /// the encryption private key and self-encryption key the atServer held.
  ///
  /// This PKAMs on its own connection, built from `pending.atKeys`: [atLookUp]
  /// belongs to whoever submitted the request and cannot sign with a key that
  /// did not exist when it was constructed.
  ///
  /// On success `pending.atKeys` is complete and has been persisted to
  /// [atKeysIo], ready for client creation. Denial throws
  /// [AtEnrollmentException]. See `example/enrollment_request.dart`.
  Future<void> waitForApproval(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo,
    PendingEnrollment pending, {
    bool logProgress = true,
    int maxRetries = defaultMaxRetries,
    Duration retryInterval = defaultRetryInterval,
  });
}
