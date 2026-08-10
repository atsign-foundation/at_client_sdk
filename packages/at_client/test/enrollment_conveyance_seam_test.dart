// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client/src/enroll/enrollment_conveyance.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

class _RecordingAtEnrollment extends Mock implements AtEnrollment {
  final List<EnrollmentRequestDecision> approvals = [];

  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision decision, AtLookUp atLookUp) async {
    approvals.add(decision);
    return AtEnrollmentResponse(
        decision.enrollmentId, EnrollmentStatus.approved);
  }
}

/// An [EnrollmentConveyance] that records what approve() hands it and
/// answers with a fixed status, so these tests observe the seam rather than
/// the sealing behind it.
class _StatusConveyance implements EnrollmentConveyance {
  _StatusConveyance(this.status, {this.sweepResult = 0});

  final KeyPackageStatus status;
  final int sweepResult;
  final List<({Enrollment enrollment, String? minted})> conveyed = [];
  int sweeps = 0;

  @override
  Future<KeyPackageStatus> conveySecretsTo(Enrollment enrollment,
      {String? mintedApkamSymmetricKey}) async {
    conveyed.add((enrollment: enrollment, minted: mintedApkamSymmetricKey));
    return status;
  }

  @override
  Future<int> sweepUnanchoredEnrollments() async {
    sweeps++;
    return sweepResult;
  }
}

/// approve() consults the injected [EnrollmentConveyance] and owns the policy
/// about what its answer means: the conveyance *reports* the advertised key
/// package's status, and whether a rejected one fails the approval is decided
/// here, where the caller who can revoke is listening.
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
      'keyPackage': {
        'payload': {'v': 1},
        'signature': 's'
      }
    },
  };

  /// The legacy shape: the enrollee wrapped its own key.
  const wrappedRecord = {
    'appName': 'buzz',
    'deviceName': 'pixel',
    'namespace': {'buzz': 'rw'},
    'encryptedAPKAMSymmetricKey': 'rsa-wrapped',
    'metadata': {
      'keyPackage': {
        'payload': {'v': 1},
        'signature': 's'
      }
    },
  };

  MockAtClient approverWithPending(Map<String, Object?> record,
      {String recordEnrollmentId = enrolleeId}) {
    final approver = buildRemoteBackedMockClient(
        atSign: atSign, enrollmentId: 'approver-1', remoteData: remoteData);
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list)
        .buildCommand();
    final key = '$recordEnrollmentId.new.enrollments.__manage$atSign';
    final secondary = approver.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({key: record})}');
    return approver;
  }

  Future<AtEnrollmentResponse> approveThrough(
    _StatusConveyance conveyance, {
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

  test('the conveyance refusal still reads as an AtEnrollmentException',
      () async {
    await expectLater(
        approveThrough(_StatusConveyance(KeyPackageStatus.rejected)),
        throwsA(isA<AtEnrollmentException>()),
        reason: 'callers already catching the published exception type must '
            'keep working; the carrying type is a subtype, not a replacement');
  });

  test('an absent package approves quietly', () async {
    final conveyance = _StatusConveyance(KeyPackageStatus.absent);

    final response = await approveThrough(conveyance);

    expect(response.enrollmentId, enrolleeId);
    expect(conveyance.conveyed.single.enrollment.enrollmentId, enrolleeId,
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
    expect(minting.conveyed.single.minted, isNotNull,
        reason: 'the enrollee sent no wrapped key, so the key the approver '
            'minted is the one the conveyance must seal first');

    remoteData.clear();
    final wrapped = _StatusConveyance(KeyPackageStatus.present);
    await approveThrough(wrapped, record: wrappedRecord);
    expect(wrapped.conveyed.single.minted, isNull,
        reason: 'this enrollee wrapped its own key; minting a second one '
            'would leave it unable to unwrap anything');
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
