// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

class _RecordingAtEnrollment extends Mock implements AtEnrollment {
  @override
  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision decision, AtLookUp atLookUp,
      {AtChops? approverChops}) async {
    return AtEnrollmentResponse(
        decision.enrollmentId, EnrollmentStatus.approved);
  }
}

/// Approval conveys the approver's **held nskey privates**, read from AtKeys.
///
/// This is the push half of the self-heal ruling (`decisions.md` 38), and the
/// specific hole it closes: `shareAllSecretsWith` shares from the in-memory
/// secret store, which after a restart holds nothing — so an approver that
/// had restarted since the mint conveyed a new enrollment every secret except
/// the namespace privates it actually needs to read anything. The durable
/// copy in AtKeys is what must be conveyed, whatever the store holds.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'enrollee-1';
  const namespace = 'buzz';
  late Map<String, String> remoteData;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() => remoteData = {});

  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = buildRemoteBackedMockClient(
        atSign: atSign, enrollmentId: enrollmentId, remoteData: remoteData);
    // The sweep enumerates envelope keys by scan, which the shared fixture
    // does not stub.
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

  void stubPendingEnrollment(AtClient approver, Object keyPackage) {
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list)
        .buildCommand();
    final key = '$enrolleeId.new.enrollments.__manage$atSign';
    final secondary = approver.getRemoteSecondary()!;
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

  test('an approver conveys its filed nskey privates to the new enrollment',
      () async {
    // The enrollee advertises a key package, as a real enroll:request does.
    final enrollee =
        AtClientSecretSharing.forClient(buildMockClient(enrolleeId));
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();

    // The approver holds one nskey private — in AtKeys, as a client that
    // restarted since the mint would: its in-memory secret store is EMPTY,
    // which is exactly the state the old path conveyed nothing from.
    final approver = buildMockClient('approver-1');
    final approverIo = InMemoryAtKeysIo();
    await approverIo.write(atSign, AtKeys());
    when(() => approver.atKeysIo).thenReturn(approverIo);
    final pair = await XWingKeyPair.generate();
    final kid = nskeyKidOf(pair.publicKeyBytes);
    await NskeyPrivateFiling(keysIo: approverIo, atSign: atSign).store(
        namespace: namespace,
        nskeyKid: kid,
        seed: NskeySeed(pair.privateKeyBytes));
    await AtClientSecretSharing.forClient(approver).register();

    stubPendingEnrollment(approver, advertised);
    await EnrollmentServiceImpl(approver, _RecordingAtEnrollment()).approve(
        EnrollmentRequestDecision.approved(
            enrollmentId: enrolleeId,
            apkamSymmetricKey: AtBytes.fromString(''),
            atSign: atSign));

    // The enrollee receives it over the ordinary substrate delivery.
    expect(await enrollee.sweepOnce(), greaterThan(0),
        reason: 'nothing arrived at all — the approval conveyed no envelope '
            'this enrollee can consume');
    final received = enrollee.secretStore
        .getSecret(namespace, '${NskeyPrivateFiling.secretNamePrefix}$kid');
    expect(received, isNotNull,
        reason: 'the approver held this namespace\'s private in AtKeys and '
            'approved an enrollment for that namespace, so the private must '
            'arrive — this is the conveyance hole of decisions.md 38');
    expect(base64Decode(received!.value), pair.privateKeyBytes,
        reason: 'and byte-exact, or the enrollee files a key that opens '
            'nothing');
  });

  test('an approver with no atKeysIo approves cleanly and conveys none',
      () async {
    final enrollee =
        AtClientSecretSharing.forClient(buildMockClient(enrolleeId));
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();

    final approver = buildMockClient('approver-2');
    when(() => approver.atKeysIo).thenReturn(null);
    await AtClientSecretSharing.forClient(approver).register();
    stubPendingEnrollment(approver, advertised);

    final response =
        await EnrollmentServiceImpl(approver, _RecordingAtEnrollment()).approve(
            EnrollmentRequestDecision.approved(
                enrollmentId: enrolleeId,
                apkamSymmetricKey: AtBytes.fromString(''),
                atSign: atSign));

    expect(response.enrollmentStatus, EnrollmentStatus.approved,
        reason: 'the push is best-effort: a client with no durable key source '
            'must still approve — the enrollee heals by pulling at its next '
            'start');
  });
}
