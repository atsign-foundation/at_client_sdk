import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/spec/ml_dsa_65_spec.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:test/test.dart';

void main() {
  group('ML-DSA-65 pure-Dart', () {
    test('instance generateKeyPair produces FIPS 204 key sizes', () async {
      // Pins the generateKeyPair conversion from a static method to an
      // instance method (required to implement AtSignatureAlgorithm).
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      expect(kp.publicKey.length, equals(1952));
      expect(kp.secretKey.length, equals(4032));

      final Uint8List message = Uint8List.fromList('instance keygen'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);
      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isTrue);
    });

    test('sign/verify round-trip yields true', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('Hello ML-DSA-65'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: sk);
      final bool ok =
          await algo.verifyBytes(message, signature: sig, publicKey: pub);

      expect(ok, isTrue);
    });

    test('Generated key pair has FIPS 204 sizes', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(1952));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(4032));
    });

    test('Signature has expected FIPS 204 length (3309 bytes)', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List sig = await MlDsa65PureDartAlgo()
          .signBytes(Uint8List.fromList('test'.codeUnits), secretKey: sk);

      expect(sig.length, equals(3309));
    });

    test('Verifying with wrong public key returns false', () async {
      final MlDsa65KeyPair kp1 = await MlDsa65KeyPair.generate();
      final MlDsa65KeyPair kp2 = await MlDsa65KeyPair.generate();
      final Uint8List sk = base64Decode(kp1.atPrivateKey.privateKey);
      final Uint8List wrongPub = base64Decode(kp2.atPublicKey.publicKey);

      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: sk);
      final bool ok =
          await algo.verifyBytes(message, signature: sig, publicKey: wrongPub);

      expect(ok, isFalse);
    });

    test('Verifying tampered message returns false', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: sk);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      final bool ok =
          await algo.verifyBytes(tampered, signature: sig, publicKey: pub);

      expect(ok, isFalse);
    });

    test('Deprecated stateful sign/verify via AtSigningAlgorithm still works',
        () async {
      // The stateful path shipped in 3.3.0 and AtChopsImpl's
      // signing/verification dispatch is typed against AtSigningAlgorithm,
      // so it must keep working until it is removed in a major release.
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlDsa65PureDartAlgo();
      // ignore: deprecated_member_use_from_same_package
      algo.secretKey = sk;

      final Uint8List message = Uint8List.fromList('Hello'.codeUnits);
      // ignore: deprecated_member_use_from_same_package
      final Uint8List sig = await algo.sign(message);
      // ignore: deprecated_member_use_from_same_package
      final bool ok = await algo.verify(
        message,
        sig,
        publicKey: kp.atPublicKey.publicKey,
      );

      expect(ok, isTrue);
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

    test(
        'verifyBytes returns false (never throws) for a wrong-length public key',
        () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);
      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: sk);

      final Uint8List badPub = Uint8List(MlDsa65Sizes.publicKeyBytes - 1);
      final bool ok =
          await algo.verifyBytes(message, signature: sig, publicKey: badPub);

      expect(ok, isFalse);
    });

    test(
        'verifyBytes returns false (never throws) for a wrong-length signature',
        () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List badSig = Uint8List(MlDsa65Sizes.signatureBytes + 1);
      final bool ok = await MlDsa65PureDartAlgo()
          .verifyBytes(message, signature: badSig, publicKey: pub);

      expect(ok, isFalse);
    });

    test(
        'MlDsa65KeyPair.create throws AtSigningException for a wrong-length public key',
        () {
      final String badPub =
          base64Encode(Uint8List(MlDsa65Sizes.publicKeyBytes - 1));
      final String sk = base64Encode(Uint8List(MlDsa65Sizes.secretKeyBytes));

      expect(() => MlDsa65KeyPair.create(badPub, sk),
          throwsA(isA<AtSigningException>()));
    });

    test(
        'MlDsa65KeyPair.create throws AtSigningException for a wrong-length secret key',
        () {
      final String pub = base64Encode(Uint8List(MlDsa65Sizes.publicKeyBytes));
      final String badSk =
          base64Encode(Uint8List(MlDsa65Sizes.secretKeyBytes + 1));

      expect(() => MlDsa65KeyPair.create(pub, badSk),
          throwsA(isA<AtSigningException>()));
    });

    test(
        'MlDsa65KeyPair.create throws AtSigningException for invalid base64 public key',
        () {
      final String validSk =
          base64Encode(Uint8List(MlDsa65Sizes.secretKeyBytes));

      expect(() => MlDsa65KeyPair.create('!!!invalid-base64!!!', validSk),
          throwsA(isA<AtSigningException>()));
    });

    test(
        'MlDsa65KeyPair.create throws AtSigningException for invalid base64 secret key',
        () {
      final String validPub =
          base64Encode(Uint8List(MlDsa65Sizes.publicKeyBytes));

      expect(() => MlDsa65KeyPair.create(validPub, '!!!invalid-base64!!!'),
          throwsA(isA<AtSigningException>()));
    });

    // The wrong-length cases above never reach pqcrypto — the length gate
    // rejects them first, so they say nothing about what MlDsa.verify does
    // with input it actually sees. These two do reach it, and pin the
    // "never throws" half of verifyBytes' contract for the pure-Dart backend
    // the way ml_dsa_65_ffi_test.dart pins it for the FFI one.
    test('verifyBytes returns false for a right-length garbage public key',
        () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig =
          await algo.signBytes(message, secretKey: kp.secretKey);

      final Uint8List garbagePub = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.publicKeyBytes, (int i) => (i * 7 + 13) % 256));

      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: garbagePub),
          isFalse);
    });

    test('verifyBytes returns false for a right-length garbage signature',
        () async {
      final algo = MlDsa65PureDartAlgo();
      final kp = await algo.generateKeyPair();
      final Uint8List message = Uint8List.fromList('data'.codeUnits);

      final Uint8List garbageSig = Uint8List.fromList(List<int>.generate(
          MlDsa65Sizes.signatureBytes, (int i) => (i * 11 + 29) % 256));

      expect(
          await algo.verifyBytes(message,
              signature: garbageSig, publicKey: kp.publicKey),
          isFalse);
    });
  });
}
