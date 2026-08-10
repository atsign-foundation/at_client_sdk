import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show KeyPackageStatus;
import 'package:meta/meta.dart' show experimental;

/// Conveys to an approved enrollment the secrets its approval entitles it
/// to: its symmetric key when the approver minted one, an approval-chain
/// link, the signing root when it is fully privileged, the nskey privates
/// for its namespaces, and the existing app secrets they authorise.
///
/// One injected seam rather than the approval verb wrapper owning the
/// sealing itself: what to convey is substrate policy, while whether a
/// conveyance outcome fails the approval is the *caller's* policy — so
/// implementations report the advertised key package's [KeyPackageStatus]
/// and never enforce a response to it.
@experimental
abstract interface class EnrollmentConveyance {
  /// Conveys everything [enrollment]'s approval entitles it to, and reports
  /// the status of the key package it advertised.
  ///
  /// Nothing is conveyed unless the package verifies
  /// ([KeyPackageStatus.present]): an enrollment that advertised none
  /// ([KeyPackageStatus.absent]) or one this version cannot read
  /// ([KeyPackageStatus.unsupported]) is left alone — the first is ordinary
  /// during rollout and for the self-retrofit path, and neither is anything
  /// the caller can fix. A package that was advertised and refused
  /// ([KeyPackageStatus.rejected]) is reported rather than thrown, so the
  /// caller can decide what a just-approved device that will be unable to
  /// decrypt anything means for the approval it has already performed.
  ///
  /// [mintedApkamSymmetricKey] is the key the approver minted on the
  /// enrollment's behalf, when the request carried none of its own; it is
  /// conveyed first, because the enrollee is blocked polling for exactly
  /// that envelope.
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment,
      {String? mintedApkamSymmetricKey});

  /// Signs and conveys approval-chain links for approved enrollments that
  /// lack one.
  ///
  /// A scoped enrollment can never anchor itself (not fully privileged —
  /// correctly), and its approver is often the legacy parent enrollment,
  /// which can sign nothing. Left alone, *chained-but-unanchored is its
  /// permanent state*, costing the defence-in-depth the chain exists for. A
  /// fully privileged client is the one party that can repair that, so it
  /// sweeps: every approved enrollment with a discoverable key package and
  /// no published link gets one signed and conveyed. The enrollment stamps
  /// it onto its own `_apsk` at its next start — this client cannot stamp
  /// it directly, because `_apsk` accepts writes only from its own
  /// enrollment's connection, and that restriction is the very guarantee
  /// the chain hangs off.
  ///
  /// The caller is responsible for privilege: a link signed by an
  /// unanchored enrollment adds a hop without reaching the root. Returns
  /// how many links were conveyed.
  Future<int> sweepUnanchoredEnrollments();
}
