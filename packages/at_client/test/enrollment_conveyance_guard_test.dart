// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;

import 'test_utils/envelope_tamper.dart';
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

/// Conveying an enrollment's symmetric key seals it from the *approver's* own
/// key package, so an approver that never registered one cannot do it.
///
/// This became reachable only with the reversal: an approver with no secrets
/// to convey never got as far as sealing anything, and now every pq approval
/// does. Left alone it surfaced as a bare `Bad state: register() has not been
/// called` from inside the substrate, thrown *after* the enrollment had
/// already been approved — so the device was live and would never receive its
/// key, and the message said nothing about either fact.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'enrollee-1';
  late Map<String, String> remoteData;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() => remoteData = {});

  MockAtClient buildMockClient(String enrollmentId) =>
      buildRemoteBackedMockClient(
          atSign: atSign, enrollmentId: enrollmentId, remoteData: remoteData);

  /// Stubs `enroll:list` to return one pending enrollment carrying [keyPackage]
  /// and **no** `encryptedAPKAMSymmetricKey` — the shape that asks this
  /// approver to mint and convey.
  void stubPendingEnrollment(AtClient approver, Object keyPackage) {
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list)
        .buildCommand();
    final key = '$enrolleeId.new.enrollments.__manage$atSign';
    // Resolve the secondary first: nesting the call inside `when` would
    // register the stub against getRemoteSecondary itself.
    final secondary = approver.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  key: {
                    'appName': 'buzz',
                    'deviceName': 'pixel',
                    'namespace': {'buzz': 'rw'},
                    'metadata': {'keyPackage': keyPackage},
                  }
                })}');
  }

  /// An enrollee that has registered, so its `_apsk` is published and the
  /// package it advertises verifies against it.
  Future<SignedEnvelope> advertisedKeyPackage() async {
    final enrollee =
        AtClientSecretSharing.forClient(buildMockClient(enrolleeId));
    await enrollee.register();
    return await enrollee.signedKeyPackagePayload();
  }

  Future<AtEnrollmentResponse> approveWith(AtClient approver) =>
      EnrollmentServiceImpl(approver, _RecordingAtEnrollment()).approve(
          EnrollmentRequestDecision.approved(
              enrollmentId: enrolleeId,
              apkamSymmetricKey: AtBytes.fromString(''),
              atSign: atSign));

  test('an approver with no key package is told what to call', () async {
    final approver = buildMockClient('approver-1');
    stubPendingEnrollment(approver, (await advertisedKeyPackage()).toJson());

    await expectLater(
        approveWith(approver),
        throwsA(isA<AtEnrollmentException>()
            .having((e) => e.message, 'message', contains('register()'))),
        reason: 'the approver has just approved a device that cannot receive '
            'its key, so the error has to name the fix rather than surface a '
            'Bad state from inside the substrate');
  });

  test('an approver that has registered conveys the key', () async {
    final approver = buildMockClient('approver-1');
    await AtClientSecretSharing.forClient(approver).register();
    stubPendingEnrollment(approver, (await advertisedKeyPackage()).toJson());

    await approveWith(approver);

    // The envelope is the observable: a key addressed to the enrollee's
    // package, carrying the reserved secret name.
    final envelopes = remoteData.keys.where((k) => k.contains('.__ssenv.'));
    expect(envelopes, isNotEmpty,
        reason: 'this is the whole point of the reversal — without an '
            'envelope the enrollment authenticates and can decrypt nothing');
  });

  test('a received per-enrollment secret is never forwarded on', () async {
    final approver = buildMockClient('approver-1');
    final sharing = AtClientSecretSharing.forClient(approver);
    await sharing.register();

    // Model what an enrollment holds after being conveyed its own key
    // material: it lands in the very store shareAllSecretsWith iterates,
    // because putIfNewer accepts reserved names so that system secrets can
    // flow between a client's enrollments at all.
    await sharing.secretStore.putSecret(
        Secret(
            namespace: 'buzz',
            name: enrollmentApkamSymmetricKeySecretName,
            value: 'this-enrollment-only'),
        allowReservedName: true);
    await sharing.secretStore.putSecret(
        Secret(namespace: 'buzz', name: 'app-secret', value: 'shareable'));

    final recipient =
        AtClientSecretSharing.forClient(buildMockClient('enrollee-2'));
    final shared = await sharing.shareAllSecretsWith(await recipient.register(),
        approvedNamespaces: {'buzz': 'rw'});

    // The count is the observable, not the envelope bodies: those are sealed,
    // so grepping them for the secret's plaintext would pass whether or not it
    // was forwarded.
    expect(shared, 1,
        reason: 'the app secret goes and the per-enrollment one does not — '
            'material addressed to a single enrollment must not reach the '
            'next one it approves, and the namespace check alone would let it '
            'through since both live in buzz');
  });

  group('the signing root private', () {
    /// An approver that genuinely holds a root private, so a test of the
    /// privilege gate cannot pass merely because there was nothing to convey.
    Future<MockAtClient> rootHoldingApprover() async {
      final approver = buildMockClient('approver-1');
      final io = InMemoryAtKeysIo();
      await io.write(
          atSign,
          AtKeys()
            ..addKey(AtKeysMaterial(
              keyId: PqSigningRoot.keyId,
              keyPartType: CryptographicKeyType.privateSigning,
              keyAlgorithmType: KeyAlgorithmType.mlDsa65,
              bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 7))),
              createdAt: DateTime.now().toUtc(),
            )));
      when(() => approver.atKeysIo).thenReturn(io);
      await AtClientSecretSharing.forClient(approver).register();
      return approver;
    }

    /// Approves an enrollment granted [namespaces] and returns how many
    /// envelopes were sealed to it.
    Future<int> envelopeCountFor(Map<String, String> namespaces) async {
      remoteData.clear();
      final approver = await rootHoldingApprover();
      final listCommand = (EnrollVerbBuilder()
            ..operation = EnrollOperationEnum.list)
          .buildCommand();
      final key = '$enrolleeId.new.enrollments.__manage$atSign';
      // Built once: `enroll:list` is read twice per approval, and registering
      // a fresh enrollee on each call would publish a different `_apsk` and
      // sign the package with a different key each time.
      final keyPackage = await advertisedKeyPackage();
      final secondary = approver.getRemoteSecondary()!;
      when(() => secondary.executeCommand(listCommand, auth: true))
          .thenAnswer((_) async => 'data:${jsonEncode({
                    key: {
                      'appName': 'buzz',
                      'deviceName': 'pixel',
                      'namespace': namespaces,
                      'encryptedAPKAMSymmetricKey': 'rsa-wrapped',
                      'metadata': {'keyPackage': keyPackage},
                    }
                  })}');

      await EnrollmentServiceImpl(approver, _RecordingAtEnrollment()).approve(
          EnrollmentRequestDecision.approved(
              enrollmentId: enrolleeId,
              apkamSymmetricKey:
                  AtBytes.fromString(base64Encode(utf8.encode('wrapped'))),
              atSign: atSign));

      return remoteData.keys.where((k) => k.contains('.__ssenv.')).length;
    }

    test('reaches a fully privileged enrollment and no other', () async {
      final privileged =
          await envelopeCountFor({'*': 'rw', '__manage': 'rw', 'buzz': 'rw'});
      final scoped = await envelopeCountFor({'buzz': 'rw'});

      expect(privileged, scoped + 1,
          reason: 'the root vouches for every enrollment on the atSign, so a '
              'namespace-scoped one must never hold it — and the approver '
              'held a private in both runs, so the difference is the privilege '
              'gate rather than there having been nothing to send');
    });

    test('classifies privilege from the granted namespaces', () {
      expect(
          EnrollmentServiceImpl.isFullyPrivileged(
              {'*': 'rw', '__manage': 'rw'}),
          isTrue);
      expect(EnrollmentServiceImpl.isFullyPrivileged({'*': 'rw'}), isFalse,
          reason: 'approving is a __manage power; * alone is not the class '
              'that holds the root');
      expect(
          EnrollmentServiceImpl.isFullyPrivileged({'*': 'r', '__manage': 'rw'}),
          isFalse,
          reason: 'read-only on * is not full privilege');
      expect(EnrollmentServiceImpl.isFullyPrivileged(null), isFalse);
    });
  });

  test('a tampered key package is refused through the real conveyance',
      () async {
    final approver = buildMockClient('approver-1');
    await AtClientSecretSharing.forClient(approver).register();
    // Inside the signatures entry: a top-level `signature` member is not
    // where the verifier looks, so overwriting one would leave the real
    // signature intact and the "tampered" package would verify. The type is
    // what makes that spelling impossible now.
    final tampered = (await advertisedKeyPackage())
        .withEntryMember('signature', b64u('not the signature'));
    stubPendingEnrollment(approver, tampered.toJson());

    await expectLater(
        approveWith(approver),
        throwsA(isA<EnrollmentConveyanceException>().having(
            (e) => e.keyPackageStatus,
            'keyPackageStatus',
            KeyPackageStatus.rejected)),
        reason: 'this drives the whole chain — the real verification '
            'classifies the tampered signature as rejected, the real '
            'conveyance reports it, and approve() refuses with the response '
            'riding — where the seam test above it only pins the policy '
            'against a fake');
  });

  test('the guard does not fire when there is nothing to convey', () async {
    final approver = buildMockClient('approver-1');
    // Same enrollment, except it wrapped its own key: the legacy path, where
    // this approver mints nothing and so needs no package of its own.
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
                    'namespace': {'buzz': 'rw'},
                    'encryptedAPKAMSymmetricKey': 'rsa-wrapped',
                  }
                })}');

    await expectLater(approveWith(approver), completes,
        reason: 'an unregistered approver must still be able to approve a '
            'legacy enrollment exactly as before — the new requirement '
            'applies only where conveyance actually happens');
  });
}
