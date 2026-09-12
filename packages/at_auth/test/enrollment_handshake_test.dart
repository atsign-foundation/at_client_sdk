import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/pkam_pin.dart';

/// `AtLookupImpl` implements `AtLookupMuxable`, so this double has the seam.
class MockAtLookUp extends Mock implements AtLookupImpl {}

/// The frozen interface alone: no authenticator seam, only the credential
/// fields.
class MockPlainLookUp extends Mock implements AtLookUp {}

/// Runs an installed [AtAuthenticator] for real and records what it sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}

/// What one poll of the approval handshake runs into.
enum Poll {
  /// The atServer answered: this enrollment has not been decided yet.
  pending,

  /// The atServer could not be reached at all.
  unreachable,

  /// The atServer refused for a reason that is neither "not yet decided" nor
  /// "denied" — here, the enrollment was revoked while the wait was running.
  /// No amount of waiting turns this into an approval.
  refused,

  /// The atServer answered: PKAM succeeded, so the enrollment was approved.
  approved,
}

void main() {
  const atSign = '@alice🛠';

  final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

  /// An enrollee's keys as `submit` leaves them for the handshake: the APKAM
  /// keypair, the atSign's encryption public key, the symmetric key, and
  /// neither of the two secrets the handshake is about to fetch. This one
  /// holds the demo RSA keypair, which is the PKAM pin's key.
  AtKeys rsaKeys() => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(pkamPublicKeyMap[atSign]!)
    ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(encryptionPublicKeyMap[atSign]!)
    ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey);

  AtEnrollmentResponse responseFor(AtKeys keys) =>
      AtEnrollmentResponse('123', EnrollmentStatus.pending,
          atSign: atSign,
          rootDomain: AtRootDomain.atsignDomain,
          atAuthKeys: keys);

  /// Stubs [lookup]'s PKAM polls to run into [script], one entry per poll,
  /// and its post-approval key fetches to succeed. Returns the polls as they
  /// happen.
  Future<List<Poll>> stubLookUp(AtLookUp lookup, List<Poll> script) async {
    // Sealed the way an approver seals them, under the legacy IV the record
    // then carries none of.
    final sealer = AESEncryptionAlgo(AESKey(apkamSymmetricKey));
    Future<String> sealed(String value) async => base64.encode(await sealer
        .encrypt(Uint8List.fromList(utf8.encode(value)),
            iv: InitialisationVector.legacy()));

    final sealedPrivateKey = await sealed(encryptionPrivateKeyMap[atSign]!);
    final sealedSelfKey = await sealed(aesKeyMap[atSign]!);

    final polled = <Poll>[];
    when(() => lookup.pkamAuthenticate(enrollmentId: '123'))
        .thenAnswer((_) async {
      final outcome =
          polled.length < script.length ? script[polled.length] : Poll.approved;
      polled.add(outcome);
      switch (outcome) {
        case Poll.pending:
          throw UnAuthenticatedException('error:AT0401 enrollment is pending');
        case Poll.unreachable:
          throw AtLookUpException('AT0021', 'the atServer is unreachable');
        case Poll.refused:
          throw UnAuthenticatedException(
              'error:AT0027:enrollment_id: 123 is revoked');
        case Poll.approved:
          return true;
      }
    });
    when(() => lookup.executeCommand(
        any(that: startsWith('keys:get:keyName:123.default_enc_private_key')),
        auth:
            any(named: 'auth'))).thenAnswer(
        (_) async => 'data:${jsonEncode({'value': sealedPrivateKey})}');
    when(() => lookup.executeCommand(
            any(that: startsWith('keys:get:keyName:123.default_self_enc_key')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => 'data:${jsonEncode({'value': sealedSelfKey})}');
    return polled;
  }

  /// A handshake rig around a lookup that has the authenticator seam, whose
  /// PKAM polls run into [script] and whose key fetches succeed — so the only
  /// thing under observation is how the handshake responds to the script.
  Future<(AtEnrollmentResponse, MockAtLookUp, List<Poll>)> rig(
      List<Poll> script,
      {AtKeys? keys}) async {
    final lookup = MockAtLookUp();
    final polled = await stubLookUp(lookup, script);
    return (responseFor(keys ?? rsaKeys()), lookup, polled);
  }

  /// Runs the authenticator [lookup] was handed against a recorded challenge
  /// and returns the `pkam:` command it sent.
  Future<String> pkamSentBy(MockAtLookUp lookup) async {
    final installed = verify(() => lookup.authenticator = captureAny())
        .captured
        .single as AtAuthenticator;
    final executor =
        _RecordingExecutor(['data:$pkamPinChallenge', 'data:success']);
    expect(await installed(executor), isTrue);
    return executor.sent.last;
  }

  Future<void> waitFor(
          AtEnrollmentResponse response, MockAtLookUp lookup, int maxRetries) =>
      AtEnrollmentImpl().waitForApproval(response,
          atLookup: lookup,
          maxRetries: maxRetries,
          retryInterval: const Duration(milliseconds: 1),
          logProgress: false);

  group('the retry budget', () {
    test('is never spent by an enrollment nobody has decided yet', () async {
      // Whoever approves this does so on their own schedule, so a pending
      // answer is not a failure and a wait for one is deliberately unbounded.
      final script = List.filled(20, Poll.pending);
      final (response, lookup, polled) = await rig(script);

      await waitFor(response, lookup, 2);

      expect(polled.length, 21,
          reason: 'twenty pending polls against a budget of two, and the '
              'twenty-first poll is the one that found it approved');
    });

    test('survives more unreachable polls than the budget, spread out',
        () async {
      // Two failures, an answer, two more, an answer, two more: six failures
      // against a budget of two, but never three in a row. Reaching the
      // atServer is what the budget measures, so each answer restores it.
      final (response, lookup, polled) = await rig([
        Poll.unreachable,
        Poll.unreachable,
        Poll.pending,
        Poll.unreachable,
        Poll.unreachable,
        Poll.pending,
        Poll.unreachable,
        Poll.unreachable,
        Poll.approved,
      ]);

      await waitFor(response, lookup, 2);

      expect(polled.where((p) => p == Poll.unreachable).length, 6,
          reason: 'the wait rode out every one of them');
      expect(response.atAuthKeys!.defaultEncryptionPrivateKey!.toString(),
          encryptionPrivateKeyMap[atSign]!);
    });

    test('is exhausted by consecutive unreachable polls', () async {
      // The escape hatch from an atServer that is genuinely gone: one more
      // consecutive failure than the budget allows, and the cause propagates
      // rather than being swallowed into another retry.
      final (response, lookup, polled) =
          await rig(List.filled(9, Poll.unreachable));

      await expectLater(
          waitFor(response, lookup, 2), throwsA(isA<AtLookUpException>()));

      expect(polled.length, 3,
          reason: 'two failures tolerated, the third fatal');
    });

    test('is exhausted by a refusal the wait cannot resolve', () async {
      // Neither pending nor denied: an enrollment revoked while the wait was
      // running answers `AT0027`, and no amount of waiting turns that into an
      // approval. Before this branch existed the refusal matched none of the
      // three handled codes and fell out of the catch unlogged and unthrown,
      // so the poll ran every retryInterval for the life of the process
      // saying nothing.
      final (response, lookup, polled) =
          await rig(List.filled(9, Poll.refused));

      await expectLater(
          waitFor(response, lookup, 2),
          throwsA(isA<AtEnrollmentException>()
              .having((e) => e.message, 'message', contains('AT0027'))),
          reason: 'the atServer said why; the exception must carry it');

      expect(polled.length, 3,
          reason: 'two tolerated in case it is transient, the third fatal');
    });

    test('a refusal between pending answers does not end the wait', () async {
      // Bounded, not hair-trigger: one odd refusal surrounded by ordinary
      // pending answers is transient, and an approval still lands.
      final (response, lookup, polled) = await rig([
        Poll.pending,
        Poll.refused,
        Poll.pending,
        Poll.refused,
        Poll.pending,
        Poll.approved,
      ]);

      await waitFor(response, lookup, 2);

      expect(polled.length, 6);
      expect(response.atAuthKeys!.defaultEncryptionPrivateKey!.toString(),
          encryptionPrivateKeyMap[atSign]!,
          reason: 'the wait completed and unwrapped the keys');
    });
  });

  group('what the handshake installs on the lookup', () {
    test('an authenticator, and not the credential ladder', () async {
      // Which wiring authenticates was covered by nothing: removing the
      // authenticator outright left every test in this file green, because
      // the lookup is mocked past the point where it would be used. This
      // asserts the wiring itself.
      final (response, lookup, _) = await rig([Poll.approved]);

      await AtEnrollmentImpl().waitForApproval(response, atLookup: lookup);

      // The setter call, not the stored value: a mock does not keep what is
      // assigned to it.
      verify(() => lookup.authenticator = any(that: isNotNull)).called(1);
      verifyNever(() => lookup.atChops = any());
      verifyNever(() => lookup.signingAlgoType = SigningAlgoType.rsa2048);
      verifyNever(() => lookup.signingAlgoType = SigningAlgoType.mldsa65);
    });

    test('and that authenticator signs the PKAM with the enrollment keypair',
        () async {
      final (response, lookup, _) = await rig([Poll.approved]);
      await AtEnrollmentImpl().waitForApproval(response, atLookup: lookup);

      final pkam = await pkamSentBy(lookup);

      expect(pkam, contains(':enrollmentId:123:'),
          reason: 'the handshake authenticates as the enrollment being '
              'approved, or the atServer answers for the wrong principal');
      expect(pkam, endsWith(':$expectedPkamSignature\n'),
          reason: 'the bytes openssl produces for this challenge under this '
              'key: what signs may move, the signature may not');
    });

    test('an ML-DSA enrollment signs with its typed keypair, and it verifies',
        () async {
      // The shape submit leaves for a PQ enrollee: the keypair's bytes in the
      // flat fields, which carry no algorithm, and typed material under the
      // enrollment id, which does. ML-DSA signatures are randomised, so the
      // check is the verifier's rather than a byte pin.
      final pair = await MlDsa65PureDartAlgo().generateKeyPair();
      final keys = rsaKeys()
        ..apkamPublicKey = AtBytes(pair.publicKey)
        ..apkamPrivateKey = AtBytes(pair.secretKey)
        ..fileApkamMaterial(
            enrollmentId: '123',
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: base64Encode(pair.publicKey),
            privateKey: base64Encode(pair.secretKey));
      final (response, lookup, _) = await rig([Poll.approved], keys: keys);
      await AtEnrollmentImpl().waitForApproval(response, atLookup: lookup);

      final pkam = await pkamSentBy(lookup);

      expect(pkam, contains(':signingAlgo:mldsa65:'),
          reason: 'the algorithm comes from the typed material; the default '
              'would sign an ML-DSA key with the RSA routine');
      final signature =
          base64Decode(pkam.substring(pkam.lastIndexOf(':') + 1).trim());
      expect(
          MlDsa65PureDartAlgo.verifyBytesSync(
              Uint8List.fromList(utf8.encode(pkamPinChallenge)),
              signature: signature,
              publicKey: pair.publicKey),
          isTrue,
          reason: 'signed over the challenge bytes directly, as the atServer '
              'verifies mldsa65');
    });

    test('a lookup without the seam gets the credential fields instead',
        () async {
      final lookup = MockPlainLookUp();
      await stubLookUp(lookup, [Poll.approved]);

      await AtEnrollmentImpl()
          .waitForApproval(responseFor(rsaKeys()), atLookup: lookup);

      verify(() => lookup.atChops = any(that: isNotNull)).called(1);
      // The demo keypair is RSA and names no other algorithm.
      verifyNever(() => lookup.signingAlgoType = SigningAlgoType.mldsa65);
    });
  });

  group('the published polling regime', () {
    test('is these numbers', () {
      // Raw literals on purpose. These ARE the published defaults, so a
      // change to one has to be a deliberate edit here, and that edit is the
      // review — asserting them against the constants that declare them
      // would follow any change silently.
      expect(AtEnrollment.defaultRetryInterval, const Duration(seconds: 2));
      expect(AtEnrollment.defaultMaxRetries, 15);
      expect(AtEnrollment.defaultLogProgress, true);
    });

    test('is what a caller stating no preference actually gets', () async {
      // Observes the applied default rather than the declared one. Dart
      // resolves a default in the callee, so what a caller gets is the
      // implementation's list whichever type it holds — which is why the
      // interface declaring a different list was a documentation defect
      // rather than a behavioural one. `logProgress` is the member of the
      // list with a visible effect on a single successful poll.
      final (response, lookup, _) = await rig([Poll.approved]);
      final enrollment = AtEnrollmentImpl();
      final events = <Object>[];
      final subscription = enrollment.progressStream.listen(events.add);

      await enrollment.waitForApproval(response, atLookup: lookup);
      await subscription.cancel();

      expect(events, isNotEmpty,
          reason: 'a wait that states no preference narrates itself');
    });
  });
}
