/// The approving app's decision on an enrollment request: approve it, deny it,
/// or revoke one already approved.
///
/// The request arrives as a notification from the atServer. The approving app —
/// any app whose keys include the "__manage" namespace — decides, and approval
/// grants the requesting app authentication plus authorization to the namespaces
/// it asked for.
///
/// This type is sealed and there is one subtype per operation, each carrying only
/// what its operation needs. `AtEnrollment.approve`/`deny`/`revoke` accept their
/// own subtype, so a decision cannot be handed to the wrong operation:
///
/// | operation | type                    | beyond [enrollmentId]         |
/// | --------- | ----------------------- | ----------------------------- |
/// | approve   | [EnrollmentApproval]    | `encryptedApkamSymmetricKey`  |
/// | deny      | [EnrollmentDenial]      | —                             |
/// | revoke    | [EnrollmentRevocation]  | `force`                       |
///
/// ```dart
/// // Approve — the encryptedApkamSymmetricKey comes from the notification or
/// // from `AtEnrollment.list`, on ServerEnrollmentRequest.
/// await atEnrollment.approve(
///     EnrollmentRequestDecision.approved(
///       enrollmentId: request.enrollmentId,
///       encryptedApkamSymmetricKey: request.encryptedAPKAMSymmetricKey!,
///     ),
///     atLookUp,
///     mySession);
///
/// // Deny — the requesting app is prevented from authenticating to the atServer.
/// await atEnrollment.deny(
///     EnrollmentRequestDecision.denied(request.enrollmentId),
///     atLookUp,
///     mySession);
///
/// // Revoke an already-approved enrollment.
/// await atEnrollment.revoke(
///     EnrollmentRequestDecision.revoked(enrollmentId),
///     atLookUp,
///     mySession);
/// ```
///
/// The atsign the decision concerns is not on the decision — it comes from the
/// approving app's own `AtAuthSession`, which `approve`/`deny`/`revoke` take
/// alongside it.
sealed class EnrollmentRequestDecision {
  /// The enrollment being decided on, as notified by the atServer.
  final String enrollmentId;

  const EnrollmentRequestDecision(this.enrollmentId);

  /// Approves the enrollment [enrollmentId].
  ///
  /// [encryptedApkamSymmetricKey] is the requesting app's APKAM symmetric key as
  /// held by the atServer — encrypted with the approver's default encryption
  /// public key at submit time. `AtEnrollment.approve` decrypts it with the
  /// approver's encryption *private* key, then re-encrypts the default encryption
  /// private key and the self encryption key under it and sends those to the
  /// atServer. The requesting app decrypts them to read shared and self data.
  static EnrollmentApproval approved({
    required String enrollmentId,
    required String encryptedApkamSymmetricKey,
  }) =>
      EnrollmentApproval(
        enrollmentId,
        encryptedApkamSymmetricKey: encryptedApkamSymmetricKey,
      );

  /// Denies the enrollment [enrollmentId], preventing the requesting app from
  /// authenticating to the atServer.
  static EnrollmentDenial denied(String enrollmentId) =>
      EnrollmentDenial(enrollmentId);

  /// Revokes the approved enrollment [enrollmentId], closing its active
  /// connections and making it unusable.
  ///
  /// A client cannot revoke the enrollment it is itself authenticated under
  /// unless [force] is true.
  static EnrollmentRevocation revoked(String enrollmentId,
          {bool force = false}) =>
      EnrollmentRevocation(enrollmentId, force: force);
}

/// A decision to approve an enrollment. Build with
/// [EnrollmentRequestDecision.approved].
final class EnrollmentApproval extends EnrollmentRequestDecision {
  /// The requesting app's APKAM symmetric key, encrypted with the approver's
  /// default encryption public key — base64, exactly as the atServer supplies it
  /// on the enrollment record (`ServerEnrollmentRequest.encryptedAPKAMSymmetricKey`).
  final String encryptedApkamSymmetricKey;

  const EnrollmentApproval(super.enrollmentId,
      {required this.encryptedApkamSymmetricKey});
}

/// A decision to deny an enrollment. Build with
/// [EnrollmentRequestDecision.denied].
final class EnrollmentDenial extends EnrollmentRequestDecision {
  const EnrollmentDenial(super.enrollmentId);
}

/// A decision to revoke an approved enrollment. Build with
/// [EnrollmentRequestDecision.revoked].
final class EnrollmentRevocation extends EnrollmentRequestDecision {
  /// Permits revoking the enrollment the current client is authenticated under.
  /// The atServer rejects that revocation unless this is set.
  final bool force;

  const EnrollmentRevocation(super.enrollmentId, {this.force = false});
}
