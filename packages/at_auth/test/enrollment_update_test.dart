/// `enroll:update` — an approved enrollment amending its own record.
///
/// The proof-of-possession signature is a **cross-tier** contract: this side
/// composes it and every atServer implementation verifies it, and neither
/// compiles against the other. So the tests that matter here do not assert that
/// the signer produced *a* signature — they re-run the atServer's own
/// verification, transcribed from its source, over what the signer emitted.
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

/// The atServer's verification of `apkamPublicKeySignature`, transcribed from
/// `ApkamSignatureVerifier.verify` in at_secondary_server.
///
/// Transcribed rather than approximated, and the two branches are the whole
/// point: `mldsa65` verifies the message bytes **directly**, while everything
/// else goes through at_chops with SHA-256. A client that hashed for both would
/// pass every RSA test ever written for it and fail only against a
/// post-quantum key, which is exactly the failure this file exists to catch.
Future<bool> asTheAtServerVerifies({
  required String signable,
  required String base64Signature,
  required String publicKey,
  required SigningAlgoType signingAlgo,
}) async {
  final message = utf8.encode(signable);
  final signature = base64Decode(base64Signature);

  if (signingAlgo == SigningAlgoType.mldsa65) {
    return await MlDsa65PureDartAlgo().verifyBytes(message,
        signature: signature, publicKey: base64Decode(publicKey));
  }
  final input = AtSigningVerificationInput(message, signature, publicKey)
    ..signingAlgoType = signingAlgo
    ..hashingAlgoType = HashingAlgoType.sha256
    ..signingMode = AtSigningMode.pkam;
  return await AtChopsImpl(AtChopsKeys.create(null, null)).verify(input).result;
}

void main() {
  const atSign = '@alice🛠';
  const enrollmentId = 'e-1';

  /// A lookup that records every command and answers with an approved update.
  ({MockAtLookUp lookUp, List<String> commands}) lookUp(
      {String response =
          'data:{"enrollmentId":"$enrollmentId","status":"approved"}'}) {
    final mock = MockAtLookUp();
    final commands = <String>[];
    when(() => mock.executeCommand(any(), auth: true)).thenAnswer((inv) async {
      commands.add(inv.positionalArguments[0] as String);
      return response;
    });
    return (lookUp: mock, commands: commands);
  }

  /// The JSON an `enroll:update` command carries, past its prefix.
  Map<String, dynamic> paramsOf(String command) {
    expect(command, startsWith('enroll:update:'));
    expect(command, endsWith('\n'));
    return jsonDecode(command.substring(
        'enroll:update:'.length, command.length - 1)) as Map<String, dynamic>;
  }

  group('the possession proof verifies the way the atServer verifies it', () {
    test('rsa2048 — signed over the SHA-256, as the pkam path signs', () async {
      final publicKey = pkamPublicKeyMap[atSign]!;
      final privateKey = pkamPrivateKeyMap[atSign]!;

      final signature = apkamPossessionSignature(
          enrollmentId: enrollmentId,
          apkamPublicKey: publicKey,
          apkamPrivateKey: privateKey,
          signingAlgo: SigningAlgoType.rsa2048);

      expect(
          await asTheAtServerVerifies(
              signable: '$enrollmentId|$publicKey|rsa2048',
              base64Signature: signature,
              publicKey: publicKey,
              signingAlgo: SigningAlgoType.rsa2048),
          isTrue);
    });

    test('mldsa65 — signed over the message DIRECTLY, with no hash', () async {
      final pair = await MlDsa65KeyPair.generate();
      final publicKey = pair.atPublicKey.publicKey;

      final signature = apkamPossessionSignature(
          enrollmentId: enrollmentId,
          apkamPublicKey: publicKey,
          apkamPrivateKey: pair.atPrivateKey.privateKey,
          signingAlgo: SigningAlgoType.mldsa65);

      expect(
          await asTheAtServerVerifies(
              signable: '$enrollmentId|$publicKey|mldsa65',
              base64Signature: signature,
              publicKey: publicKey,
              signingAlgo: SigningAlgoType.mldsa65),
          isTrue,
          reason: 'the atServer hands ML-DSA the raw message; a signer that '
              'hashed first would produce a signature over the wrong bytes '
              'and this is the only arm that can see it');
    });

    test('a signature over a DIFFERENT enrollment id does not verify',
        () async {
      final publicKey = pkamPublicKeyMap[atSign]!;

      final signature = apkamPossessionSignature(
          enrollmentId: 'some-other-enrollment',
          apkamPublicKey: publicKey,
          apkamPrivateKey: pkamPrivateKeyMap[atSign]!,
          signingAlgo: SigningAlgoType.rsa2048);

      expect(
          await asTheAtServerVerifies(
              signable: '$enrollmentId|$publicKey|rsa2048',
              base64Signature: signature,
              publicKey: publicKey,
              signingAlgo: SigningAlgoType.rsa2048),
          isFalse,
          reason: 'the enrollment id is inside the signed bytes, so a proof '
              'made for one enrollment cannot be replayed onto another');
    });

    test('an algorithm this side cannot sign for is refused, not guessed', () {
      expect(
          () => apkamPossessionSignature(
              enrollmentId: enrollmentId,
              apkamPublicKey: 'PUB',
              apkamPrivateKey: 'PRIV',
              signingAlgo: SigningAlgoType.ecc_secp256r1),
          throwsA(isA<AtEnrollmentException>()),
          reason: "at_chops' pkam-mode signer selects an RSA implementation "
              'for everything that is not mldsa65, so an ECC key would be '
              'signed as though it were RSA');
    });
  });

  group('the enroll:update command', () {
    test('an advertisement update sends the composed array and nothing else',
        () async {
      final l = lookUp();

      await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(enrollmentId: enrollmentId, signingKeys: [
            ApskSigningKey.forPublicKey(
                alg: SigningAlgoType.mldsa65, pub: 'AAEC'),
            ApskSigningKey.forPublicKey(
                alg: SigningAlgoType.rsa2048, pub: 'CCEC'),
          ]),
          l.lookUp);

      expect(
          l.commands.single,
          'enroll:update:{"enrollmentId":"e-1","apsk":{"v":1,"keys":['
          '{"kid":"ae4b3280e56e2faf","use":"sign","alg":"mldsa65","pub":"AAEC"},'
          '{"kid":"f4a1915927abe756","use":"sign","alg":"rsa2048","pub":"CCEC"}'
          ']}}\n',
          reason: 'the kid is derived by the composer from the key material — '
              'it is never a value a caller supplies, because two spellings '
              'of it address different keys and both compile. Both digests '
              'were computed outside this tree, so the pin cannot follow the '
              'implementation it is checking: python3 -c "import '
              'hashlib,base64; print(hashlib.sha256(base64.b64decode(X))'
              '.hexdigest()[:16])"');
    });

    test('a rotation sends the new public key, its algorithm and the proof',
        () async {
      final l = lookUp();
      final publicKey = pkamPublicKeyMap[atSign]!;

      await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(
            enrollmentId: enrollmentId,
            apkamPublicKey: publicKey,
            apkamPrivateKey: pkamPrivateKeyMap[atSign]!,
            signingAlgo: SigningAlgoType.rsa2048,
          ),
          l.lookUp);

      final params = paramsOf(l.commands.single);
      expect(params.keys.toList(),
          ['enrollmentId', 'apkamPublicKey', 'signingAlgo',
            'apkamPublicKeySignature']);
      expect(params['apkamPublicKey'], publicKey);
      expect(params['signingAlgo'], 'rsa2048');
      // The proof the atServer will run, over exactly what was sent — not over
      // what the test believes was sent.
      expect(
          await asTheAtServerVerifies(
              signable: '$enrollmentId|${params['apkamPublicKey']}|'
                  '${params['signingAlgo']}',
              base64Signature: params['apkamPublicKeySignature'] as String,
              publicKey: params['apkamPublicKey'] as String,
              signingAlgo: SigningAlgoType.rsa2048),
          isTrue);
    });

    test('the private half never reaches the wire', () async {
      final l = lookUp();
      final privateKey = pkamPrivateKeyMap[atSign]!;

      await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(
            enrollmentId: enrollmentId,
            apkamPublicKey: pkamPublicKeyMap[atSign]!,
            apkamPrivateKey: privateKey,
            signingAlgo: SigningAlgoType.rsa2048,
          ),
          l.lookUp);

      expect(l.commands.single.contains(privateKey), isFalse);
    });

    test('the bare legacy form rides apskLegacy, unquoted as JSON', () async {
      final l = lookUp();

      await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(
              enrollmentId: enrollmentId,
              apskLegacy: 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A'),
          l.lookUp);

      expect(
          l.commands.single,
          'enroll:update:{"enrollmentId":"e-1",'
          '"apskLegacy":"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A"}\n');
    });

    test('a metadata update carries the map and touches nothing else',
        () async {
      final l = lookUp();

      await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(
              enrollmentId: enrollmentId, metadata: {'keyPackage': 'kp'}),
          l.lookUp);

      expect(l.commands.single,
          'enroll:update:{"enrollmentId":"e-1","metadata":{"keyPackage":"kp"}}\n');
    });

    test('it runs authenticated, on the enrollment it names', () async {
      final l = lookUp();

      await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(
              enrollmentId: enrollmentId, metadata: {'a': 'b'}),
          l.lookUp);

      verify(() => l.lookUp.executeCommand(any(), auth: true)).called(1);
    });

    test('the response is the enrollment id and its status', () async {
      final l = lookUp();

      final response = await AtEnrollmentImpl().update(
          EnrollmentUpdateRequest(
              enrollmentId: enrollmentId, metadata: {'a': 'b'}),
          l.lookUp);

      expect(response.enrollmentId, enrollmentId);
      expect(response.enrollStatus, EnrollmentStatus.approved);
    });

    test('a server refusal is thrown, not parsed as a response', () async {
      final l = lookUp(response: 'error:AT0009:enroll:update is self-only');

      expect(
          () => AtEnrollmentImpl().update(
              EnrollmentUpdateRequest(
                  enrollmentId: enrollmentId, metadata: {'a': 'b'}),
              l.lookUp),
          throwsA(isA<AtEnrollmentException>()),
          reason: 'jsonDecode on an error: line throws something that says '
              'nothing about what the atServer refused');
    });
  });

  group('what the request refuses to be built as', () {
    test('an update naming nothing to change', () {
      expect(() => EnrollmentUpdateRequest(enrollmentId: enrollmentId),
          throwsA(isA<AtEnrollmentException>()));
    });

    test('a public key with no private half to prove it', () {
      expect(
          () => EnrollmentUpdateRequest(
              enrollmentId: enrollmentId,
              apkamPublicKey: 'PUB',
              signingAlgo: SigningAlgoType.rsa2048),
          throwsA(isA<AtEnrollmentException>()));
    });

    test('a key with no algorithm, and an algorithm with no key', () {
      expect(
          () => EnrollmentUpdateRequest(
              enrollmentId: enrollmentId,
              apkamPublicKey: 'PUB',
              apkamPrivateKey: 'PRIV'),
          throwsA(isA<AtEnrollmentException>()),
          reason: 'the effective algorithm goes into the signed bytes, so a '
              'client that omits it has to already know what the record holds');
      expect(
          () => EnrollmentUpdateRequest(
              enrollmentId: enrollmentId,
              signingAlgo: SigningAlgoType.mldsa65,
              metadata: {'a': 'b'}),
          throwsA(isA<AtEnrollmentException>()),
          reason: 'the atServer refuses an algorithm with no key: the '
              'algorithm describes the key, and PKAM verification is '
              'record-authoritative');
    });

    test('both _apsk shapes at once', () {
      expect(
          () => EnrollmentUpdateRequest(
              enrollmentId: enrollmentId,
              signingKeys: [
                ApskSigningKey.forPublicKey(
                    alg: SigningAlgoType.rsa2048, pub: 'AAEC')
              ],
              apskLegacy: 'MIIBIjAN'),
          throwsA(isA<AtEnrollmentException>()),
          reason: 'one enrollment publishes one _apsk value, and the atServer '
              'has no basis for choosing between two descriptions of one '
              'record');
    });

    test('an advertisement of no keys at all', () {
      expect(
          () => EnrollmentUpdateRequest(
              enrollmentId: enrollmentId, signingKeys: []),
          throwsA(isA<AtEnrollmentException>()),
          reason: 'every reader refuses an advertisement it understands '
              'nothing in, which would leave this enrollment unable to have '
              'anything it signs verified');
    });
  });
}
