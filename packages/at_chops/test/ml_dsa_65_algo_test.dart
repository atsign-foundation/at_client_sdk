import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('ML-DSA-65 pure-Dart', () {
    test('sign/verify round-trip yields true', () async {
      final AtMlDsa65KeyPair kp = await AtChopsUtil.generateMlDsa65KeyPair();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List message =
          Uint8List.fromList('Hello ML-DSA-65'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(message, sk);
      final bool ok = await MlDsa65PureDartAlgo.verifyBytes(message, sig, pub);

      expect(ok, isTrue);
    });

    test('Generated key pair has FIPS 204 sizes', () async {
      final AtMlDsa65KeyPair kp = await AtChopsUtil.generateMlDsa65KeyPair();
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(1952));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(4032));
    });

    test('Signature has expected FIPS 204 length (3309 bytes)', () async {
      final AtMlDsa65KeyPair kp = await AtChopsUtil.generateMlDsa65KeyPair();
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(
          Uint8List.fromList('test'.codeUnits), sk);

      expect(sig.length, equals(3309));
    });

    test('Verifying with wrong public key returns false', () async {
      final AtMlDsa65KeyPair kp1 = await AtChopsUtil.generateMlDsa65KeyPair();
      final AtMlDsa65KeyPair kp2 = await AtChopsUtil.generateMlDsa65KeyPair();
      final Uint8List sk = base64Decode(kp1.atPrivateKey.privateKey);
      final Uint8List wrongPub = base64Decode(kp2.atPublicKey.publicKey);

      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(message, sk);
      final bool ok =
          await MlDsa65PureDartAlgo.verifyBytes(message, sig, wrongPub);

      expect(ok, isFalse);
    });

    test('Verifying tampered message returns false', () async {
      final AtMlDsa65KeyPair kp = await AtChopsUtil.generateMlDsa65KeyPair();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(message, sk);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      final bool ok =
          await MlDsa65PureDartAlgo.verifyBytes(tampered, sig, pub);

      expect(ok, isFalse);
    });

    test('Stateful sign/verify via AtSigningAlgorithm interface', () async {
      final AtMlDsa65KeyPair kp = await AtChopsUtil.generateMlDsa65KeyPair();
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlDsa65PureDartAlgo();
      algo.secretKey = sk;

      final Uint8List message = Uint8List.fromList('Hello'.codeUnits);
      final Uint8List sig = await algo.sign(message);
      final bool ok = await algo.verify(
        message,
        sig,
        publicKey: kp.atPublicKey.publicKey,
      );

      expect(ok, isTrue);
    });
  });
}
