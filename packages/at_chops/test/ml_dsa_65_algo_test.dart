import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/types.dart';
import 'package:test/test.dart';

void main() {
  group('ML-DSA-65 pure-Dart', () {
    test('sign/verify round-trip yields true', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List message = Uint8List.fromList('Hello ML-DSA-65'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(message, sk);
      final bool ok = await MlDsa65PureDartAlgo.verifyBytes(message, sig, pub);

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

      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(
          Uint8List.fromList('test'.codeUnits), sk);

      expect(sig.length, equals(3309));
    });

    test('Verifying with wrong public key returns false', () async {
      final MlDsa65KeyPair kp1 = await MlDsa65KeyPair.generate();
      final MlDsa65KeyPair kp2 = await MlDsa65KeyPair.generate();
      final Uint8List sk = base64Decode(kp1.atPrivateKey.privateKey);
      final Uint8List wrongPub = base64Decode(kp2.atPublicKey.publicKey);

      final Uint8List message = Uint8List.fromList('data'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(message, sk);
      final bool ok =
          await MlDsa65PureDartAlgo.verifyBytes(message, sig, wrongPub);

      expect(ok, isFalse);
    });

    test('Verifying tampered message returns false', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);

      final Uint8List message = Uint8List.fromList('original'.codeUnits);
      final Uint8List sig = await MlDsa65PureDartAlgo.signBytes(message, sk);

      final Uint8List tampered = Uint8List.fromList('tampered'.codeUnits);
      final bool ok = await MlDsa65PureDartAlgo.verifyBytes(tampered, sig, pub);

      expect(ok, isFalse);
    });

    test('signBytes/verifyBytes via AtSignatureAlgorithm interface', () async {
      final MlDsa65KeyPair kp = await MlDsa65KeyPair.generate();
      final Uint8List sk = base64Decode(kp.atPrivateKey.privateKey);
      final Uint8List pk = base64Decode(kp.atPublicKey.publicKey);

      final AtSignatureAlgorithm algo = const MlDsa65PureDartSigner();
      final Uint8List message = Uint8List.fromList('Hello'.codeUnits);
      final Uint8List sig = await algo.signBytes(message, sk);
      final bool ok = await algo.verifyBytes(message, sig, pk);

      expect(ok, isTrue);
    });
  });
}
