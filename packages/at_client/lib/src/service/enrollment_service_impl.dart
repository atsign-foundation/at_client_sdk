import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AtChopsUtil, EncryptionKeyType;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/enroll/enrollment_conveyance.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart' as privilege;
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show KeyPackageStatus;
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/envelope_enrollment_conveyance.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/at_builders.dart';

class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollment _atEnrollmentImpl;
  final EnrollmentConveyance? _injectedConveyance;

  /// What approval seals to the newly approved device. Defaults to the
  /// envelope-sealing conveyance, listing enrollments through this service's
  /// own verb wrapper.
  late final EnrollmentConveyance _conveyance = _injectedConveyance ??
      EnvelopeEnrollmentConveyance(_atClient,
          listEnrollments: fetchEnrollmentRequests);

  EnrollmentServiceImpl(this._atClient, this._atEnrollmentImpl,
      {EnrollmentConveyance? conveyance})
      : _injectedConveyance = conveyance;

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

  /// Signs and conveys approval-chain links for approved enrollments that
  /// lack one — see [EnrollmentConveyance.sweepUnanchoredEnrollments].
  Future<int> sweepUnanchoredEnrollments() =>
      _conveyance.sweepUnanchoredEnrollments();

  /// Whether [namespaces] grant `rw` on both `*` and `__manage` — the class
  /// that may hold the signing root. See [privilege.isFullyPrivileged].
  static bool isFullyPrivileged(Map<String, dynamic>? namespaces) =>
      privilege.isFullyPrivileged(namespaces);

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    // Read the pending record before approving. A request that sent no wrapped
    // symmetric key is one that expects this approver to mint it — that
    // absence is the whole signal, and it is only visible while the record is
    // still the one the enrollee wrote. Its advertised key package alone would
    // not do: every mode may carry one, because a package is also how existing
    // secrets are sealed to a new device.
    final pending =
        await _enrollmentById(enrollmentRequestDecision.enrollmentId);
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
      final KeyPackageStatus status;
      try {
        status = await _conveyance.conveySecretsTo(enrollment,
            mintedApkamSymmetricKey: mintedApkamSymmetricKey);
      } on EnrollmentConveyanceException {
        rethrow;
      } on AtEnrollmentException catch (e) {
        // A thrown refusal — the unregistered-approver guard, the
        // no-ordinary-namespace refusal — fires just as much after the
        // successful server-side approval as a rejected package does, so it
        // carries the response the same way. The package itself was fine as
        // far as the conveyance got, which is what `present` records here.
        throw EnrollmentConveyanceException(e.message,
            response: response, keyPackageStatus: KeyPackageStatus.present);
      }
      if (status == KeyPackageStatus.rejected) {
        // The approval has already happened on the atServer, so refusing
        // loudly here is what lets the approver learn what it has approved —
        // and the response rides along so the refusal cannot cost the caller
        // the evidence of that success.
        throw EnrollmentConveyanceException(
            'Enrollment ${enrollment.enrollmentId} is approved, but the key '
            'package it advertised does not verify against its _apsk, so no '
            'secrets were shared with it and it will be unable to decrypt '
            'anything. Revoke it unless this is understood.',
            response: response,
            keyPackageStatus: status);
      }
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
