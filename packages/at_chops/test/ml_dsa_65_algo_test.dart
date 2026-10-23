import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:test/test.dart';

void main() {
  group('ML-DSA-65 pure-Dart', () {
    test('name is the wire identifier, independent of SigningAlgoType', () {
      expect(MlDsa65PureDartAlgo().name, equals('mldsa65'));
      expect(MlDsa65PureDartAlgo().name, equals(SigningAlgoType.mldsa65.name),
          reason: 'a downstream protocol keys its wire/record/keystore '
              'format on this literal');
    });

    test('generateKeyPair produces FIPS 204 key sizes', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      expect(kp.publicKey.length, equals(1952));
      expect(kp.secretKey.length, equals(4032));

      final Uint8List message = Uint8List.fromList('instance keygen'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);
      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: kp.publicKey),
          completes);
    });

    test('sign/verify round-trip completes without throwing', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();

      final Uint8List message = Uint8List.fromList('Hello ML-DSA-65'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: kp.publicKey),
          completes);
    });

    test('Signature has expected FIPS 204 length (3309 bytes)', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();

      final Uint8List sig = await algo.signBytes(
          Uint8List.fromList('test'.codeUnits),
          secretKey: kp.secretKey);

      expect(sig.length, equals(3309));
    });

    test('Verifying with wrong public key throws', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp1 = await algo.generateKeyPair();
      final kp2 = await algo.generateKeyPair();

      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp1.secretKey);

      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: kp2.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('Verifying tampered message throws', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();

      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      await expectLater(
          algo.verifyBytes(tampered, signature: sig, publicKey: kp.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
    test('MlDsa65Sizes matches pqcrypto\'s own FIPS 204 sizes', () {
      expect(MlDsa65Sizes.publicKeyBytes,
          equals(DilithiumParams.mlDsa65.publicKeyBytes));
      expect(MlDsa65Sizes.secretKeyBytes,
          equals(DilithiumParams.mlDsa65.secretKeyBytes));
      expect(MlDsa65Sizes.signatureBytes,
          equals(DilithiumParams.mlDsa65.signatureBytes));
    });

    test('signBytes throws ArgumentError for a short secret key', () async {
      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List shortSk = Uint8List(MlDsa65Sizes.secretKeyBytes - 1);

      expect(() => algo.signBytes(message, secretKey: shortSk),
          throwsA(isA<ArgumentError>()));
    });

    test('signBytes throws ArgumentError for an over-long secret key',
        () async {
      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List longSk = Uint8List(MlDsa65Sizes.secretKeyBytes + 1);

      expect(() => algo.signBytes(message, secretKey: longSk),
          throwsA(isA<ArgumentError>()));
    });

    test('verifyBytes throws for a wrong-length public key', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List badPub = Uint8List(MlDsa65Sizes.publicKeyBytes - 1);
      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: badPub),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('verifyBytes throws for a wrong-length signature', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List badSig = Uint8List(MlDsa65Sizes.signatureBytes + 1);
      await expectLater(
          algo.verifyBytes(message,
              signature: badSig, publicKey: kp.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });

    // The wrong-length cases above never reach pqcrypto — the length gate
    // rejects them first, so they say nothing about what MlDsa.verify does
    // with input it actually sees. These two do reach it, and pin that a
    // verification failure from pqcrypto itself takes the same exit as a
    // length rejection.
    test('verifyBytes throws for a right-length garbage public key', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List garbagePub = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.publicKeyBytes, (int i) => (i * 7 + 13) % 256));

      await expectLater(
          algo.verifyBytes(message, signature: sig, publicKey: garbagePub),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('verifyBytes throws for a right-length garbage signature', () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List garbageSig = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.signatureBytes, (int i) => (i * 11 + 29) % 256));

      await expectLater(
          algo.verifyBytes(message,
              signature: garbageSig, publicKey: kp.publicKey),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });
}
