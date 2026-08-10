import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
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
  });
}
