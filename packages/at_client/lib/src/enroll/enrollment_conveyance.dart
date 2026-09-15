import 'package:at_auth/at_auth.dart' show AtEnrollmentResponse;
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show KeyPackageStatus;
import 'package:at_commons/at_commons.dart' show AtEnrollmentException;
import 'package:meta/meta.dart' show experimental;

/// Conveys to an enrollment the secrets its approval entitles it to: its
/// symmetric key when the approver minted one, before the approval, and
/// after it an approval-chain link, the signing root when it is fully
/// privileged, the nskey privates for its namespaces, and the existing app
/// secrets they authorise.
///
/// Whether a conveyance outcome fails the approval is the *caller's* policy,
/// so implementations report the advertised key package's [KeyPackageStatus]
/// and never enforce a response to it.
@experimental
abstract interface class EnrollmentConveyance {
  /// Conveys everything [enrollment]'s approval entitles it to, and reports
  /// the status of the key package it advertised.
  ///
  /// Nothing is conveyed unless the package verifies
  /// ([KeyPackageStatus.present]): an enrollment that advertised none
  /// ([KeyPackageStatus.absent]) or one this version cannot read
  /// ([KeyPackageStatus.unsupported]) is left alone, neither being anything
  /// the caller can fix. A package that was advertised and refused
  /// ([KeyPackageStatus.rejected]), or whose check could not be completed
  /// because its `_apsk` could not be fetched ([KeyPackageStatus.unverified]),
  /// is reported rather than thrown, so the caller can decide what a
  /// just-approved device that will be unable to decrypt anything means for
  /// the approval it has already performed.
  ///
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment);

  /// Seals [apkamSymmetricKey], minted on [pending]'s behalf, to the key
  /// package its request advertised, before the approval that encrypts under
  /// it.
  ///
  /// The package is not checked against `_apsk`, which the atServer publishes
  /// only at approval and which that same atServer would serve. Conveys
  /// nothing when there is no package this version can read, and throws
  /// [AtEnrollmentException] when this client has no key package to seal from.
  Future<void> conveyMintedApkamSymmetricKey(
      Enrollment pending, String apkamSymmetricKey);

  /// Signs and conveys **root** links for approved enrollments that are not
  /// yet root-anchored.
  ///
  /// A scoped enrollment can never anchor itself, and its approver may be able
  /// to sign nothing at all or only a provisional chain link, so unanchored is
  /// its permanent state unless a fully privileged client — `rw` on `*` and
  /// `__manage`, the class entitled to hold the signing root — repairs it.
  /// Every approved enrollment with a discoverable key package and no
  /// published *root* link gets one signed with the root private and conveyed.
  /// The enrollment verifies it against the published signing root and stamps
  /// it onto its own `_apsk` at its next start; this client cannot stamp it
  /// directly, because `_apsk` accepts writes only from its own enrollment's
  /// connection, and that restriction is the guarantee the anchoring hangs
  /// off.
  ///
  /// The caller is responsible for privilege. Returns how many links were
  /// conveyed.
  Future<int> sweepUnanchoredEnrollments();
}

/// An approval whose server-side approve **succeeded** but whose conveyance
/// refused the advertised key package ([KeyPackageStatus.rejected]) — the
/// enrollment is live and will be unable to decrypt anything, and the
/// approver can revoke it.
///
/// Carries the approval [response] so refusing the conveyance cannot cost
/// the caller the evidence that the approval itself happened: a plain throw
/// here would report a server-side success as a failure, which is how an
/// approver ends up retrying an approval that already went through.
@experimental
class EnrollmentConveyanceException extends AtEnrollmentException {
  /// The successful server-side approval this exception is *not* about.
  final AtEnrollmentResponse response;

  /// The advertised key package's status when the conveyance stopped:
  /// [KeyPackageStatus.rejected] when the package itself was the refusal,
  /// [KeyPackageStatus.unverified] when its check could not be completed,
  /// [KeyPackageStatus.present] when the package was fine and the conveyance
  /// refused for another reason — the message says which.
  final KeyPackageStatus keyPackageStatus;

  EnrollmentConveyanceException(super.message,
      {required this.response, required this.keyPackageStatus});
}
