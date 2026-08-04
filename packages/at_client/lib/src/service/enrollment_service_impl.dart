import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AtChopsUtil, EncryptionKeyType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/secret_sharing/enrollment_symmetric_key.dart'
    show enrollmentApkamSymmetricKeySecretName;
import 'package:at_commons/at_builders.dart';

class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollment _atEnrollmentImpl;

  EnrollmentServiceImpl(this._atClient, this._atEnrollmentImpl);

  @override
  Future<List<Enrollment>> fetchEnrollmentRequests(
      {EnrollmentListRequestParam? enrollmentListParams}) async {
    EnrollVerbBuilder enrollBuilder = EnrollVerbBuilder()
      ..operation = EnrollOperationEnum.list
      ..appName = enrollmentListParams?.appName
      ..deviceName = enrollmentListParams?.deviceName
      ..enrollmentStatusFilter = enrollmentListParams?.enrollmentListFilter;

    String? response = await _atClient
        .getRemoteSecondary()!
        .executeCommand(enrollBuilder.buildCommand(), auth: true);

    return _formatEnrollListResponse(response!);
  }

  String extractEnrollmentId(String enrollmentKey) {
    return enrollmentKey.split('.')[0];
  }

  List<Enrollment> _formatEnrollListResponse(String response) {
    response = response.replaceFirst(RegExp('^data:'), '');
    Map<String, dynamic> enrollRequests = jsonDecode(response);
    List<Enrollment> enrollRequestsFormatted = [];
    for (MapEntry enrollmentRequest in enrollRequests.entries) {
      Enrollment enrollmentRequestResponse =
          Enrollment.fromJSON(enrollmentRequest.value);
      enrollmentRequestResponse.enrollmentId =
          extractEnrollmentId(enrollmentRequest.key);
      enrollRequestsFormatted.add(enrollmentRequestResponse);
    }
    return enrollRequestsFormatted;
  }

  /// Seals every secret [enrollment]'s namespaces authorise to the key package
  /// it advertised on its `enroll:request`, so the newly approved device can
  /// read what it has just been authorised for.
  ///
  /// Runs **after** the approval, because the atServer publishes the
  /// enrollment's `_apsk` at that point and the package cannot be verified
  /// before it exists.
  ///
  /// Throws when a package was advertised and **refused** — the approver
  /// should learn that it has just approved a device that will be unable to
  /// decrypt anything, and can revoke. An enrollment that advertised nothing,
  /// or something this version cannot read, is left alone: the first is
  /// ordinary during rollout and for the self-retrofit path, and neither is
  /// anything the approver can fix.
  Future<void> _shareSecretsWith(Enrollment enrollment,
      {String? mintedApkamSymmetricKey}) async {
    final advertised = enrollment.metadata?['keyPackage'];
    if (advertised == null) return;

    final atSign = _atClient.getCurrentAtSign()!;
    final (keyPackage, status) = await verifyAdvertisedKeyPackage(
      advertised,
      signer: AtClientEnvelopeSigner(_atClient),
      signerAtSign: atSign,
      enrollmentId: enrollment.enrollmentId!,
    );

    if (status == KeyPackageStatus.rejected) {
      throw AtEnrollmentException(
          'Enrollment ${enrollment.enrollmentId} is approved, but the key '
          'package it advertised does not verify against its _apsk, so no '
          'secrets were shared with it and it will be unable to decrypt '
          'anything. Revoke it unless this is understood.');
    }
    if (keyPackage == null) return;

    final sharing = AtClientSecretSharing.forClient(_atClient);

    // The symmetric key goes first. Everything else this enrollment is about
    // to receive is useless until it holds the key that unwraps its own
    // encryption private key, and it is blocked in waitForApproval polling for
    // exactly this envelope.
    if (mintedApkamSymmetricKey != null) {
      await sharing.shareSecretWith(
          keyPackage,
          Secret(
            namespace: _conveyanceNamespaceFor(enrollment),
            name: enrollmentApkamSymmetricKeySecretName,
            value: mintedApkamSymmetricKey,
          ));
    }

    await sharing.shareAllSecretsWith(keyPackage,
        approvedNamespaces: enrollment.namespace);
  }

  /// A namespace this enrollment is authorised to read, for the envelope
  /// carrying its symmetric key.
  ///
  /// The envelope is a self key in an app namespace, so the atServer's
  /// namespace gating decides whether the enrollment can fetch it at all —
  /// which rules out `__manage` (a device enrollment is not granted it) and
  /// `*` (not a namespace the key can live in). The atServer requires every
  /// new-client request to name at least one namespace, so there is always a
  /// candidate.
  String _conveyanceNamespaceFor(Enrollment enrollment) {
    final granted = (enrollment.namespace?.keys ?? const <String>[])
        .where((ns) => ns != '*' && ns != '__manage');
    if (granted.isEmpty) {
      throw AtEnrollmentException(
          'Enrollment ${enrollment.enrollmentId} is authorised for no ordinary '
          'namespace, so there is nowhere to put the envelope carrying its '
          'symmetric key that it would be allowed to read.');
    }
    return granted.first;
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    // Read the pending record before approving. A request that sent no wrapped
    // symmetric key is one that expects this approver to mint it — that
    // absence is the whole signal, and it is only visible while the record is
    // still the one the enrollee wrote. Its advertised key package alone would
    // not do: every mode may carry one, because a package is also how existing
    // secrets are sealed to a new device.
    final pending = await _enrollmentById(enrollmentRequestDecision.enrollmentId);
    final bool mintsSymmetricKey =
        (pending?.encryptedAPKAMSymmetricKey?.isEmpty ?? true) &&
            pending?.metadata?['keyPackage'] != null;

    String? mintedApkamSymmetricKey;
    var decision = enrollmentRequestDecision;
    if (mintsSymmetricKey) {
      mintedApkamSymmetricKey =
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
      decision = EnrollmentRequestDecision.approvedWithMintedKey(
        enrollmentId: enrollmentRequestDecision.enrollmentId,
        apkamSymmetricKey: mintedApkamSymmetricKey,
        atSign: enrollmentRequestDecision.atSign,
      );
    }

    final response = await _atEnrollmentImpl.approve(
        decision, _atClient.getRemoteSecondary()!.atLookUp);

    // Re-read the record rather than trusting the decision object: the
    // decision carries only the id and the symmetric key, while conveyance
    // needs the granted namespaces and the advertised key package, and both
    // live on the enrollment the atServer just approved. Re-read *after*
    // approval specifically, because the atServer publishes the enrollment's
    // _apsk at that point and the package cannot be verified before it exists.
    final enrollment =
        await _enrollmentById(enrollmentRequestDecision.enrollmentId);
    if (enrollment != null) {
      await _shareSecretsWith(enrollment,
          mintedApkamSymmetricKey: mintedApkamSymmetricKey);
    }

    return response;
  }

  Future<Enrollment?> _enrollmentById(String enrollmentId) async =>
      (await fetchEnrollmentRequests())
          .where((e) => e.enrollmentId == enrollmentId)
          .firstOrNull;

  @override
  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.deny(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }

  @override
  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    return _atEnrollmentImpl.revoke(
        enrollmentRequestDecision, _atClient.getRemoteSecondary()!.atLookUp);
  }
}
