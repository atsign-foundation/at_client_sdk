// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client/src/enroll/enrollment_conveyance.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

class _RecordingAtEnrollment extends Mock implements AtEnrollment {
  _RecordingAtEnrollment({this.onApprove});

  final void Function(String)? onApprove;
  final List<EnrollmentRequestDecision> approvals = [];

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision decision, AtLookUp atLookUp,
      {required ApproverKeyMaterial approverKeys}) async {
    approvals.add(decision);
    onApprove?.call('approved');
    return AtEnrollmentResponse(
        decision.enrollmentId, EnrollmentStatus.approved);
  }
}

/// An [EnrollmentConveyance] that records what approve() hands it and
/// answers with a fixed status, so these tests observe the seam rather than
/// the sealing behind it.
class _StatusConveyance implements EnrollmentConveyance {
  _StatusConveyance(this.status, {this.sweepResult = 0, this.mintRefusal});

  final KeyPackageStatus status;
  final int sweepResult;
  final AtEnrollmentException? mintRefusal;
  final List<Enrollment> conveyed = [];
  final List<String> minted = [];
  int sweeps = 0;

  @override
  Future<void> conveyMintedApkamSymmetricKey(
      Enrollment pending, String apkamSymmetricKey) async {
    if (mintRefusal != null) throw mintRefusal!;
    minted.add(apkamSymmetricKey);
  }

  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment) async {
    conveyed.add(enrollment);
    return status;
  }

  @override
  Future<int> sweepUnanchoredEnrollments() async {
    sweeps++;
    return sweepResult;
  }
}

/// An [EnrollmentConveyance] that records when each of its calls lands
/// relative to the approval.
class _OrderedConveyance implements EnrollmentConveyance {
  _OrderedConveyance(this.events);

  final List<String> events;

  @override
  Future<void> conveyMintedApkamSymmetricKey(
      Enrollment pending, String apkamSymmetricKey) async {
    events.add('minted');
  }

  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment) async {
    events.add('conveyed');
    return KeyPackageStatus.present;
  }

  @override
  Future<int> sweepUnanchoredEnrollments() async => 0;
}

/// An [EnrollmentConveyance] that refuses by throwing, the way the production
/// preconditions do.
class _ThrowingConveyance implements EnrollmentConveyance {
  _ThrowingConveyance(this.refusal);

  final AtEnrollmentException refusal;

  @override
  Future<void> conveyMintedApkamSymmetricKey(
      Enrollment pending, String apkamSymmetricKey) async {}

  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment) =>
      throw refusal;

  @override
  Future<int> sweepUnanchoredEnrollments() async => 0;
}

/// approve() consults the injected [EnrollmentConveyance] and owns the policy
/// about what its answer means.
///
/// The conveyance only *reports* the advertised key package's status; whether
/// a rejected one fails the approval is decided here.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'enrollee-1';
  late Map<String, String> remoteData;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() => remoteData = {});

  /// The shape that asks the approver to mint: a key package and no wrapped
  /// symmetric key.
  const mintingRecord = {
    'appName': 'buzz',
    'deviceName': 'pixel',
    'namespace': {'buzz': 'rw'},
    'metadata': {
      // NOTE: opaque on purpose — this seam mints on the package being
      // present, never on what it says.
      'keyPackage': {'opaque-to-this-seam': true}
    },
  };

  /// The legacy shape: the enrollee wrapped its own key.
  const wrappedRecord = {
    'appName': 'buzz',
    'deviceName': 'pixel',
    'namespace': {'buzz': 'rw'},
    'encryptedAPKAMSymmetricKey': 'rsa-wrapped',
    'metadata': {
      'keyPackage': {'opaque-to-this-seam': true}
    },
  };

  MockAtClient approverWithPending(Map<String, Object?> record,
      {String recordEnrollmentId = enrolleeId}) {
    final approver = buildRemoteBackedMockClient(
        atSign: atSign, enrollmentId: 'approver-1', remoteData: remoteData);
    stubApproverKeys(approver);
    final key = '$recordEnrollmentId.new.enrollments.__manage$atSign';
    final secondary = approver.getRemoteSecondary()!;
    stubApproveListReads(secondary, 'data:${jsonEncode({key: record})}');
    return approver;
  }

  Future<AtEnrollmentResponse> approveThrough(
    EnrollmentConveyance conveyance, {
    Map<String, Object?> record = mintingRecord,
    _RecordingAtEnrollment? enrollment,
  }) {
    final approver = approverWithPending(record);
    return EnrollmentServiceImpl(
            approver, enrollment ?? _RecordingAtEnrollment(),
            conveyance: conveyance)
        .approve(EnrollmentRequestDecision.approved(
            enrollmentId: enrolleeId,
            apkamSymmetricKey: AtBytes.fromString(''),
            atSign: atSign));
  }

  test('a rejected key package fails the approval, loudly and afterwards',
      () async {
    final conveyance = _StatusConveyance(KeyPackageStatus.rejected);
    final enrollment = _RecordingAtEnrollment();

    await expectLater(
        approveThrough(conveyance, enrollment: enrollment),
        throwsA(isA<EnrollmentConveyanceException>()
            .having((e) => e.message, 'message', contains('Revoke'))
            .having((e) => e.response.enrollmentId, 'response.enrollmentId',
                enrolleeId)
            .having((e) => e.keyPackageStatus, 'keyPackageStatus',
                KeyPackageStatus.rejected)),
        reason: 'the conveyance only reports the status; refusing is '
            'approve()\'s policy, so the approver learns it has approved a '
            'device that cannot decrypt — and the server-side approval this '
            'refusal is NOT about must ride along rather than be lost');

    expect(enrollment.approvals, hasLength(1),
        reason: 'the refusal is about conveyance, not the approval itself — '
            'the server-side approve had already happened when it fired');
    expect(conveyance.conveyed, hasLength(1));
  });

  test(
      'a key package that could not be checked fails the approval naming '
      'the check, not the package', () async {
    final conveyance = _StatusConveyance(KeyPackageStatus.unverified);
    final enrollment = _RecordingAtEnrollment();

    await expectLater(
        approveThrough(conveyance, enrollment: enrollment),
        throwsA(isA<EnrollmentConveyanceException>()
            .having(
                (e) => e.message,
                'message',
                allOf(contains('could not be checked'),
                    isNot(contains('Revoke'))))
            .having((e) => e.keyPackageStatus, 'keyPackageStatus',
                KeyPackageStatus.unverified)),
        reason: 'a fetch that failed during the check says nothing about the '
            'package, so the approver is not told to revoke a device whose '
            'package was never examined');

    expect(enrollment.approvals, hasLength(1),
        reason: 'the server-side approval had already happened');
  });

  test('the conveyance refusal still reads as an AtEnrollmentException',
      () async {
    await expectLater(
        approveThrough(_StatusConveyance(KeyPackageStatus.rejected)),
        throwsA(isA<AtEnrollmentException>()),
        reason: 'callers already catching the published exception type must '
            'keep working; the carrying type is a subtype, not a replacement');
  });

  test('every post-approval conveyance refusal carries the response', () async {
    final throwing = _ThrowingConveyance(AtEnrollmentException(
        'Enrollment $enrolleeId is authorised for no ordinary namespace, so '
        'there is nowhere to put the envelope carrying its symmetric key that '
        'it would be allowed to read.'));

    await expectLater(
        approveThrough(throwing),
        throwsA(isA<EnrollmentConveyanceException>()
            .having(
                (e) => e.message, 'message', contains('no ordinary namespace'))
            .having((e) => e.response.enrollmentId, 'response.enrollmentId',
                enrolleeId)),
        reason: 'losing the response on these paths and carrying it on the '
            'rejected one would make the no-lost-response contract depend on '
            'which way the conveyance refused');
  });

  test('an absent package approves quietly', () async {
    final conveyance = _StatusConveyance(KeyPackageStatus.absent);

    final response = await approveThrough(conveyance);

    expect(response.enrollmentId, enrolleeId);
    expect(conveyance.conveyed.single.enrollmentId, enrolleeId,
        reason: 'the conveyance is consulted with the re-read enrollment '
            'even when it turns out to have nothing to seal to');
  });

  test('an unsupported package approves quietly, like absent', () async {
    final conveyance = _StatusConveyance(KeyPackageStatus.unsupported);

    await expectLater(approveThrough(conveyance), completes,
        reason: 'a package written by a newer client is nothing the approver '
            'can fix, and refusing would block approvals across a version '
            'skew');
  });

  test('a minted key reaches the conveyance; a wrapped one means none is',
      () async {
    final minting = _StatusConveyance(KeyPackageStatus.present);
    await approveThrough(minting);
    expect(minting.minted, hasLength(1),
        reason: 'the enrollee sent no wrapped key, so the key the approver '
            'minted is the one the conveyance must seal');

    remoteData.clear();
    final wrapped = _StatusConveyance(KeyPackageStatus.present);
    await approveThrough(wrapped, record: wrappedRecord);
    expect(wrapped.minted, isEmpty,
        reason: 'this enrollee wrapped its own key; minting a second one '
            'would leave it unable to unwrap anything');
  });

  test('a minted key is conveyed before the approval that encrypts under it',
      () async {
    final events = <String>[];
    final conveyance = _OrderedConveyance(events);
    final enrollment = _RecordingAtEnrollment(onApprove: events.add);

    await approveThrough(conveyance, enrollment: enrollment);

    expect(events, ['minted', 'approved', 'conveyed'],
        reason: 'the approval encrypts the enrollment\'s keys under the '
            'minted key and cannot be repeated, so a stop between the two '
            'must leave the key already with the enrollee');
  });

  test('a minted key that cannot be conveyed leaves the enrollment pending',
      () async {
    final enrollment = _RecordingAtEnrollment();

    await expectLater(
        approveThrough(
            _StatusConveyance(KeyPackageStatus.present,
                mintRefusal: AtEnrollmentException('no key package')),
            enrollment: enrollment),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e, 'type', isNot(isA<EnrollmentConveyanceException>()))));
    expect(enrollment.approvals, isEmpty,
        reason: 'an approval with no conveyed key is one the enrollee can '
            'never decrypt, and the atServer refuses to approve it again');
  });

  test('no conveyance when the re-read finds no enrollment', () async {
    final conveyance = _StatusConveyance(KeyPackageStatus.present);
    final approver =
        approverWithPending(mintingRecord, recordEnrollmentId: 'someone-else');

    await EnrollmentServiceImpl(approver, _RecordingAtEnrollment(),
            conveyance: conveyance)
        .approve(EnrollmentRequestDecision.approved(
            enrollmentId: enrolleeId,
            apkamSymmetricKey: AtBytes.fromString(''),
            atSign: atSign));

    expect(conveyance.conveyed, isEmpty,
        reason: 'conveyance needs the granted namespaces and the advertised '
            'package off the approved record; without the record there is '
            'nothing to act on');
  });

  test('sweepUnanchoredEnrollments delegates to the conveyance', () async {
    final conveyance =
        _StatusConveyance(KeyPackageStatus.absent, sweepResult: 7);
    final approver = approverWithPending(mintingRecord);

    final swept = await EnrollmentServiceImpl(
            approver, _RecordingAtEnrollment(),
            conveyance: conveyance)
        .sweepUnanchoredEnrollments();

    expect(swept, 7);
    expect(conveyance.sweeps, 1);
  });
}
