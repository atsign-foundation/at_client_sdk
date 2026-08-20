import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// PKAM signing with an ML-DSA-65 APKAM keypair — the client half of
/// `signingAlgo:mldsa65` authentication. The keypair rides the String-typed
/// [AtPkamKeyPair] slot as base64 of the raw keys.
void main() async {
  final mlDsaKeyPair = await MlDsa65KeyPair.generate();
  final pkamKeyPair = AtPkamKeyPair.create(
      mlDsaKeyPair.atPublicKey.publicKey, mlDsaKeyPair.atPrivateKey.privateKey);
  final dataToSign =
      '_a7028ce7-aaa8-4c52-9cf4-b94ca3bdf971@alice:c2834cd4-bb16-4801-8abc-efe79cdceb8f';
  final dataInBytes = Uint8List.fromList(dataToSign.codeUnits);

  group('A group of tests for mldsa65 pkam signing and verification', () {
    test('Sign and verify round trip', () {
      final algo = PkamMlDsa65SigningAlgo(pkamKeyPair);
      final signature = algo.sign(dataInBytes);
      expect(signature.length, 3309,
          reason: 'an ML-DSA-65 signature is 3309 bytes — an RSA signature '
              'here would mean the dispatch picked the wrong algorithm');
      expect(algo.verify(dataInBytes, signature), true);
    });

    test('Verify with an explicitly passed public key', () {
      final algo = PkamMlDsa65SigningAlgo(pkamKeyPair);
      final signature = algo.sign(dataInBytes);
      expect(
          PkamMlDsa65SigningAlgo(null).verify(dataInBytes, signature,
              publicKey: mlDsaKeyPair.atPublicKey.publicKey),
          true);
    });

    test('A tampered signature fails verification', () {
      final algo = PkamMlDsa65SigningAlgo(pkamKeyPair);
      final signature = algo.sign(dataInBytes);
      signature[0] ^= 0xff;
      expect(algo.verify(dataInBytes, signature), false);
    });

    test('Signing without a keypair throws', () {
      expect(
          () => PkamMlDsa65SigningAlgo(null).sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtException &&
              e.toString().contains('pkam key pair is null'))));
    });

    test('A non-base64 private key throws a signing exception, not a crash',
        () {
      final bad = AtPkamKeyPair.create('pub', '-----BEGIN RSA PRIVATE KEY');
      expect(
          () => PkamMlDsa65SigningAlgo(bad).sign(dataInBytes),
          throwsA(predicate((e) =>
              e is AtException && e.toString().contains('base64'))));
    });
  });

  group('The AtChopsImpl pkam dispatch', () {
    final atChops =
        AtChopsImpl(AtChopsKeys.create(null, pkamKeyPair));

    test('signingAlgoType mldsa65 produces a genuine ML-DSA signature',
        () async {
      final input = AtSigningInput(dataToSign)
        ..signingAlgoType = SigningAlgoType.mldsa65
        ..signingMode = AtSigningMode.pkam;
      final result = atChops.sign(input);
      final signature = base64Decode(result.result);
      expect(signature.length, 3309);
      // Cross-verify with the independent AtSignatureAlgorithm
      // implementation: this is what the atServer's verify side does, so it
      // proves the dispatch signed ML-DSA rather than RSA-with-a-claim.
      expect(
          await MlDsa65PureDartAlgo().verifyBytes(dataInBytes,
              signature: signature,
              publicKey: mlDsaKeyPair.publicKeyBytes),
          true);
    });

    test('verification via AtChops.verify returns a bool, and true', () {
      final input = AtSigningInput(dataToSign)
        ..signingAlgoType = SigningAlgoType.mldsa65
        ..signingMode = AtSigningMode.pkam;
      final signResult = atChops.sign(input);
      final verifyInput = AtSigningVerificationInput(dataToSign,
          base64Decode(signResult.result), mlDsaKeyPair.atPublicKey.publicKey)
        ..signingAlgoType = SigningAlgoType.mldsa65
        ..signingMode = AtSigningMode.pkam;
      final verifyResult = atChops.verify(verifyInput);
      // Guards the async-Future-in-bool defect this branch used to have.
      expect(verifyResult.result, isA<bool>());
      expect(verifyResult.result, true);
    });

    test('the default rsa2048 dispatch cannot sign with ML-DSA material', () {
      final input = AtSigningInput(dataToSign)
        ..signingMode = AtSigningMode.pkam;
      // Same keys, different signingAlgoType: the arms genuinely differ —
      // RSA PEM parsing of a base64 raw ML-DSA key fails.
      expect(() => atChops.sign(input), throwsA(isA<Object>()));
    });
  });
}
