import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AESKey;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/remote_secondary.dart';
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
          {EnrollmentListRequestParam? enrollmentListParams}) =>
      listEnrollmentsOn(_atClient.getRemoteSecondary()!,
          params: enrollmentListParams);

  String extractEnrollmentId(String enrollmentKey) =>
      _enrollmentIdOf(enrollmentKey);

  /// Whether this client is configured to do post-quantum work at all.
  ///
  /// Permissive when there is no preference to ask: a client built without one
  /// has not declined post-quantum, it has said nothing.
  bool get _configuresPqProviders =>
      _atClient.getPreferences()?.posture.configuresPqProviders ?? true;

  /// Root-links the keys on approved enrollments that lack a sound root
  /// link: see [EnrollmentConveyance.sweepUnanchoredEnrollments].
  ///
  /// Rejects its future when this client's posture configures no post-quantum
  /// providers: a root link is an ML-DSA-65 signature, which such a client
  /// does not make.
  Future<int> sweepUnanchoredEnrollments() async {
    if (!_configuresPqProviders) {
      throw AtClientException.message(
          'this client\'s posture configures no post-quantum providers, so it '
          'signs no root links. Run the sweep from a client whose posture '
          'does — the enrollments it would have anchored stay unanchored and '
          'a later sweep still finds them');
    }
    return _conveyance.sweepUnanchoredEnrollments();
  }

  /// Whether [namespaces] grant `rw` on both `*` and `__manage` — the class
  /// that may hold the signing root. See [privilege.isFullyPrivileged].
  static bool isFullyPrivileged(Map<String, dynamic>? namespaces) =>
      privilege.isFullyPrivileged(namespaces);

  /// This client's encryption private key and self-encryption key, resolved by
  /// the local secondary across every tier it has.
  ///
  /// The keystore reports an absent key by throwing; here that is one tier
  /// missing, not a failure. Reaching the end with either one unresolved is a
  /// refusal rather than a null handed onward: approval seals both for the
  /// enrollee, so a client that cannot read its own material must not flip
  /// the record to approved and fail afterwards.
  Future<ApproverKeyMaterial> _approverKeys() async {
    final local = _atClient.getLocalSecondary();
    Future<String?> resolve(Future<String?> Function() read) async {
      try {
        return await read();
      } on KeyNotFoundException {
        return null;
      }
    }

    final encryptionPrivateKey =
        local == null ? null : await resolve(local.getEncryptionPrivateKey);
    final selfEncryptionKey =
        local == null ? null : await resolve(local.getEncryptionSelfKey);
    if (encryptionPrivateKey == null || selfEncryptionKey == null) {
      throw AtClientException.message(
          'approving an enrollment seals this atSign\'s encryption private '
          'key and its self-encryption key for the enrollee, and this client '
          'cannot read both of them');
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

    final approverKeys = await _approverKeys();
    var decision = enrollmentRequestDecision;
    if (mintsSymmetricKey) {
      final mintedApkamSymmetricKey = AESKey.generate(32).key;
      // NOTE: conveyed before the approval, which encrypts this enrollment's
      // keys under it and cannot be repeated: a stop in between otherwise
      // leaves an approved enrollment whose key nothing holds.
      await _conveyance.conveyMintedApkamSymmetricKey(
          pending!, mintedApkamSymmetricKey);
      decision = EnrollmentRequestDecision.approvedWithMintedKey(
        enrollmentId: enrollmentRequestDecision.enrollmentId,
        apkamSymmetricKey: mintedApkamSymmetricKey,
        atSign: enrollmentRequestDecision.atSign,
      );
    }

    final response = await _atEnrollmentImpl.approve(
        decision, _atClient.getRemoteSecondary()!.atLookUp,
        approverKeys: approverKeys);

    // NOTE: re-read after the approval, not before — the atServer publishes
    // the enrollment's _apsk at that point, and the advertised key package
    // cannot be verified until it exists.
    final enrollment = await _enrollmentById(
        enrollmentRequestDecision.enrollmentId,
        const [EnrollmentStatus.approved]);
    if (enrollment != null) {
      final KeyPackageStatus status;
      try {
        status = await _conveyance.conveySecretsTo(enrollment);
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
      if (status == KeyPackageStatus.unverified) {
        throw EnrollmentConveyanceException(
            'Enrollment ${enrollment.enrollmentId} is approved, but the key '
            'package it advertised could not be checked against its _apsk, '
            'which could not be fetched, so no secrets were shared with it '
            'and it cannot complete until they are. Nothing about the '
            'package was refused; the check needs the atServer.',
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
          EnrollmentRequestDecision enrollmentRequestDecision) =>
      _decide(EnrollVerbBuilder()
        ..enrollmentId = enrollmentRequestDecision.enrollmentId
        ..operation = EnrollOperationEnum.deny);

  @override
  Future<AtEnrollmentResponse> revoke(
          EnrollmentRequestDecision enrollmentRequestDecision) =>
      _decide(EnrollVerbBuilder()
        ..enrollmentId = enrollmentRequestDecision.enrollmentId
        ..operation = EnrollOperationEnum.revoke
        ..force = enrollmentRequestDecision.force);

  Future<AtEnrollmentResponse> _decide(EnrollVerbBuilder builder) =>
      decideEnrollmentOn(_atClient.getRemoteSecondary()!,
          '${_atClient.getCurrentAtSign()}', builder);
}

/// The enrollments `enroll:list` reports on [remote], an authenticated
/// connection, narrowed by [params].
Future<List<Enrollment>> listEnrollmentsOn(RemoteSecondary remote,
    {EnrollmentListRequestParam? params}) async {
  final builder = EnrollVerbBuilder()
    ..operation = EnrollOperationEnum.list
    ..appName = params?.appName
    ..deviceName = params?.deviceName
    ..enrollmentStatusFilter = params?.enrollmentListFilter;
  final response =
      await remote.executeCommand(builder.buildCommand(), auth: true);
  final listed = jsonDecode(response!.replaceFirst(RegExp('^data:'), ''))
      as Map<String, dynamic>;
  return [
    for (final MapEntry(:key, :value) in listed.entries)
      Enrollment.fromJSON(value)..enrollmentId = _enrollmentIdOf(key),
  ];
}

String _enrollmentIdOf(String enrollmentKey) => enrollmentKey.split('.')[0];

/// Runs the decision verb [builder] for [atSign] on [remote] and returns the
/// enrollment and status the atServer answered with.
///
/// Throws [AtEnrollmentException] when the atServer answers anything but
/// `data:`.
Future<AtEnrollmentResponse> decideEnrollmentOn(
    RemoteSecondary remote, String atSign, EnrollVerbBuilder builder) async {
  final command = builder.buildCommand();
  final response = await remote.executeVerb(builder);
  if (!response.startsWith('data:')) {
    throw AtEnrollmentException(
        '${command.trim()} for $atSign was refused: $response');
  }
  final decoded = jsonDecode(response.substring('data:'.length).trim())
      as Map<String, dynamic>;
  return AtEnrollmentResponse(decoded['enrollmentId'] as String,
      getEnrollStatusFromString(decoded['status'] as String));
}
