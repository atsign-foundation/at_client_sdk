import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AESKey;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/enroll/enrollment_conveyance.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart' as privilege;
import 'package:at_client/src/response/enrollment.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show KeyPackageStatus;
import 'package:at_client/src/service/enrollment_privilege_resolver.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/envelope_enrollment_conveyance.dart';
import 'package:at_client/src/util/enroll_list_request_param.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/at_builders.dart';

class EnrollmentServiceImpl implements EnrollmentService {
  final AtClient _atClient;
  final AtEnrollment _atEnrollmentImpl;
  final EnrollmentConveyance? _injectedConveyance;

  /// What approval seals to the newly approved device.
  late final EnrollmentConveyance _conveyance = _injectedConveyance ??
      EnvelopeEnrollmentConveyance(_atClient,
          listEnrollments: fetchEnrollmentRequests,
          privilege: EnrollmentRecordPrivilegeResolver(_atClient,
              listEnrollments: fetchEnrollmentRequests));

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

  /// Whether this client is configured to do post-quantum work at all.
  ///
  /// Permissive when there is no preference to ask: a client built without one
  /// has not declined post-quantum, it has said nothing.
  bool get _configuresPqProviders =>
      _atClient.getPreferences()?.posture.configuresPqProviders ?? true;

  /// Signs and conveys approval-chain links for approved enrollments that
  /// lack one — see [EnrollmentConveyance.sweepUnanchoredEnrollments].
  ///
  /// Rejects its future when this client's posture configures no post-quantum
  /// providers: the sweep signs links and seals secrets, which such a client
  /// cannot do.
  Future<int> sweepUnanchoredEnrollments() async {
    if (!_configuresPqProviders) {
      throw AtClientException.message(
          'this client\'s posture configures no post-quantum providers, so it '
          'cannot sign or convey approval-chain links. Run the sweep from a '
          'client whose posture does — the enrollments it would have anchored '
          'stay unanchored and a later sweep still finds them');
    }
    return _conveyance.sweepUnanchoredEnrollments();
  }

  /// Whether [namespaces] grant `rw` on both `*` and `__manage` — the class
  /// that may hold the signing root. See [privilege.isFullyPrivileged].
  static bool isFullyPrivileged(Map<String, dynamic>? namespaces) =>
      privilege.isFullyPrivileged(namespaces);

  /// This client's encryption private key and self-encryption key, resolved by
  /// the local secondary across every tier it has, or null when there is no
  /// local secondary or it holds neither, which leaves at_auth to refuse the
  /// approval.
  ///
  /// The keystore reports an absent key by throwing; here that is one tier
  /// missing, not a failure.
  Future<ApproverKeyMaterial?> _approverKeys() async {
    final local = _atClient.getLocalSecondary();
    if (local == null) return null;
    Future<String?> resolve(Future<String?> Function() read) async {
      try {
        return await read();
      } on KeyNotFoundException {
        return null;
      }
    }

    final encryptionPrivateKey = await resolve(local.getEncryptionPrivateKey);
    final selfEncryptionKey = await resolve(local.getEncryptionSelfKey);
    if (encryptionPrivateKey == null || selfEncryptionKey == null) {
      return null;
    }
    return (
      encryptionPrivateKey: encryptionPrivateKey,
      selfEncryptionKey: selfEncryptionKey,
    );
  }

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision enrollmentRequestDecision) async {
    // NOTE: an absent wrapped symmetric key is what asks this approver to mint
    // one, and it is only visible while the record is still the one the
    // enrollee wrote. `approved` is in the filter so that re-approving an
    // already-approved enrollment computes the same decision.
    final pending = await _enrollmentById(
        enrollmentRequestDecision.enrollmentId,
        const [EnrollmentStatus.pending, EnrollmentStatus.approved]);
    final bool mintsSymmetricKey =
        (pending?.encryptedAPKAMSymmetricKey?.isEmpty ?? true) &&
            pending?.metadata?['keyPackage'] != null;

    // NOTE: refuse before the approval reaches the atServer. An approval that
    // lands and then fails to mint leaves the device authorised holding none
    // of the material it was authorised for, and no later approval repairs it
    // because the request is spent.
    if (mintsSymmetricKey && !_configuresPqProviders) {
      throw AtClientException.message(
          'enrollment ${enrollmentRequestDecision.enrollmentId} expects its '
          'approver to mint and seal a symmetric key, and this client\'s '
          'posture configures no post-quantum providers. It stays pending: '
          'approve it from a client whose posture does');
    }

    String? mintedApkamSymmetricKey;
    var decision = enrollmentRequestDecision;
    if (mintsSymmetricKey) {
      mintedApkamSymmetricKey = AESKey.generate(32).key;
      decision = EnrollmentRequestDecision.approvedWithMintedKey(
        enrollmentId: enrollmentRequestDecision.enrollmentId,
        apkamSymmetricKey: mintedApkamSymmetricKey,
        atSign: enrollmentRequestDecision.atSign,
      );
    }

    final response = await _atEnrollmentImpl.approve(
        decision, _atClient.getRemoteSecondary()!.atLookUp,
        approverKeys: await _approverKeys());

    // NOTE: re-read after the approval, not before — the atServer publishes
    // the enrollment's _apsk at that point, and the advertised key package
    // cannot be verified until it exists.
    final enrollment = await _enrollmentById(
        enrollmentRequestDecision.enrollmentId,
        const [EnrollmentStatus.approved]);
    if (enrollment != null) {
      final KeyPackageStatus status;
      try {
        status = await _conveyance.conveySecretsTo(enrollment,
            mintedApkamSymmetricKey: mintedApkamSymmetricKey);
      } on EnrollmentConveyanceException {
        rethrow;
      } on AtEnrollmentException catch (e) {
        throw EnrollmentConveyanceException(e.message,
            response: response, keyPackageStatus: KeyPackageStatus.present);
      }
      if (status == KeyPackageStatus.rejected) {
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

  /// The enrollment with [enrollmentId], from an `enroll:list` narrowed to
  /// [statuses].
  Future<Enrollment?> _enrollmentById(
          String enrollmentId, List<EnrollmentStatus> statuses) async =>
      (await fetchEnrollmentRequests(
              enrollmentListParams: EnrollmentListRequestParam()
                ..enrollmentListFilter = statuses))
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
