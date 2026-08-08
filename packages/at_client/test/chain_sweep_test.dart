// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

/// The chain sweep (`decisions.md` 38.3): a fully privileged client signs and
/// conveys approval-chain links for approved enrollments that lack one.
///
/// The population it exists for: a scoped enrollment approved by the legacy
/// parent enrollment (the cloned-keyfile upgrade), which can never anchor
/// itself and whose approver could sign nothing — so without the sweep,
/// unanchored is its permanent state, not a transient one.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'scoped-1';
  const namespace = 'buzz';
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMetadata;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
  });

  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = buildRemoteBackedMockClient(
        atSign: atSign,
        enrollmentId: enrollmentId,
        remoteData: remoteData,
        remoteMetadata: remoteMetadata);
    when(() => atClient.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return Future.value(remoteData.keys
          .where((k) => regex.hasMatch(k))
          .map(AtKey.fromString)
          .toList());
    });
    when(() => atClient.delete(any())).thenAnswer((inv) {
      remoteData.remove('${inv.positionalArguments[0]}');
      return Future.value(true);
    });
    return atClient;
  }

  /// Stubs the approved-filter `enroll:list` this sweep issues.
  void stubApprovedList(AtClient sweeperClient, Object keyPackage) {
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list
          ..enrollmentStatusFilter = [EnrollmentStatus.approved])
        .buildCommand();
    final key = '$enrolleeId.new.enrollments.__manage$atSign';
    final secondary = sweeperClient.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  key: {
                    'appName': 'buzz',
                    'deviceName': 'pixel',
                    'namespace': {namespace: 'rw'},
                    'metadata': {'keyPackage': keyPackage},
                  }
                })}');
  }

  test(
      'the sweep vouches for an unanchored enrollment, and stops once it '
      'has stamped', () async {
    // The scoped enrollment: registered (its _apsk is published), approved,
    // no chain link — the state a legacy-parent approval leaves it in.
    final enrolleeClient = buildMockClient(enrolleeId);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();

    // The sweeper: a distinct, registered enrollment. Privilege is the
    // caller's gate (AtClientImpl checks it); the sweep itself is exercised
    // directly here.
    final sweeperClient = buildMockClient('sweeper-1');
    await AtClientSecretSharing.forClient(sweeperClient).register();
    stubApprovedList(sweeperClient, advertised);

    final service = EnrollmentServiceImpl(sweeperClient, AtEnrollment.create());
    expect(await service.sweepUnanchoredEnrollments(), 1,
        reason: 'one approved enrollment lacks a link, so exactly one is '
            'signed and conveyed');

    // The enrollee receives the link and stamps its own _apsk — the sweep
    // cannot stamp it directly, because _apsk accepts writes only from its
    // own enrollment's connection.
    expect(await enrollee.sweepOnce(), greaterThan(0));
    await PqSigningChain.publishPendingLink(enrolleeClient);

    final published = await PqSigningChain.readLink(sweeperClient, enrolleeId);
    expect(published, isNotNull,
        reason: 'the link must end up ON THE RECORD, where a verifier walks — '
            'a link that only ever sat in a transit store vouches for nothing');
    expect(published!['enrollmentId'], 'sweeper-1',
        reason: 'signed by the sweeper: the hop a verifier follows toward the '
            'root goes through the enrollment that vouched');

    expect(await service.sweepUnanchoredEnrollments(), 0,
        reason: 'a vouched-for enrollment is skipped — the sweep is '
            'convergent, not a broadcast that repeats forever');
  });

  test('an enrollment with no key package is skipped, not failed', () async {
    final sweeperClient = buildMockClient('sweeper-2');
    await AtClientSecretSharing.forClient(sweeperClient).register();
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list
          ..enrollmentStatusFilter = [EnrollmentStatus.approved])
        .buildCommand();
    final secondary = sweeperClient.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  'legacy-1.new.enrollments.__manage$atSign': {
                    'appName': 'old',
                    'deviceName': 'laptop',
                    'namespace': {namespace: 'rw'},
                  }
                })}');

    expect(
        await EnrollmentServiceImpl(sweeperClient, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        0,
        reason: 'a legacy enrollment has no conveyance channel and no PQ key '
            'to vouch for — skipping it is the design, not a failure');
  });
}
