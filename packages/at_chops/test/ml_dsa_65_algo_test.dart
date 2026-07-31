import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
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
      final Uint8List sig = await algo.signBytes(message, secretKey: kp.secretKey);
      expect(await algo.verifyBytes(message, signature: sig, publicKey: kp.publicKey), isTrue);
    });

    test('signingAlgoType is mldsa65, spelled as the atServer expects', () {
      expect(MlDsa65PureDartAlgo().signingAlgoType,
          equals(SigningAlgoType.mldsa65));
      // The pkam verb regex in at_commons accepts only this literal spelling,
      // so a rename of the enum member must fail here rather than at auth time.
      expect(MlDsa65PureDartAlgo().signingAlgoType.name, equals('mldsa65'));
    });

    test('sign/verify round-trip yields true', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlDsa65PureDartAlgo();
      final Uint8List message = Uint8List.fromList('Hello ML-DSA-65'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, secretKey: sk);
      final bool ok = await algo.verifyBytes(message, signature: sig, publicKey: pub);

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

      final Uint8List sig = await MlDsa65PureDartAlgo().signBytes(
          Uint8List.fromList('test'.codeUnits),
          secretKey: sk);

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
      final bool ok = await algo.verifyBytes(message, signature: sig, publicKey: wrongPub);

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
      final bool ok = await algo.verifyBytes(tampered, signature: sig, publicKey: pub);

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
  });
}
