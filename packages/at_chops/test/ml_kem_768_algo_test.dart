import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/spec/ml_kem_768_spec.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 pure-Dart', () {
    final algo = MlKem768PureDartAlgo.instance;

    test('encapsulate/decapsulate round-trip yields matching shared secrets',
        () async {
      final kp = await algo.generateKeyPair();
      final enc = await algo.encapsulate(kp.publicKey);
      final Uint8List recovered =
          await algo.decapsulate(kp.secretKey, enc.ciphertext);

      expect(recovered, equals(enc.sharedSecret));
      expect(enc.sharedSecret.length, equals(32));
    });

    test('Generated key pair has FIPS 203 key sizes', () async {
      final kp = await algo.generateKeyPair();
      expect(kp.publicKey.length, equals(1184));
      expect(kp.secretKey.length, equals(2400));
    });

    test(
        'Decapsulating tampered ciphertext does not throw and (per FIPS 203)'
        ' returns an implicit-rejection secret different from the real one',
        () async {
      final kp = await algo.generateKeyPair();
      final enc = await algo.encapsulate(kp.publicKey);

      final Uint8List tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;

      final Uint8List bad = await algo.decapsulate(kp.secretKey, tampered);
      expect(bad, isNot(equals(enc.sharedSecret)));
      expect(bad.length, equals(32));
    });

    test('encapsulate throws ArgumentError for a too-short public key',
        () async {
      final Uint8List badPub = Uint8List(MlKem768Sizes.publicKeyBytes - 1);
      expect(
          () => MlKem768PureDartAlgo.instance.encapsulate(badPub),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('ML-KEM-768 public key'))));
    });

    test('encapsulate throws ArgumentError for a too-long public key',
        () async {
      final Uint8List badPub = Uint8List(MlKem768Sizes.publicKeyBytes + 1);
      expect(
          () => MlKem768PureDartAlgo.instance.encapsulate(badPub),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('ML-KEM-768 public key'))));
    });

    test('decapsulate throws ArgumentError for a wrong-length ciphertext',
        () async {
      final kp = await MlKem768PureDartAlgo.instance.generateKeyPair();
      final Uint8List priv = kp.secretKey;
      final Uint8List badCt = Uint8List(MlKem768Sizes.ciphertextBytes + 1);

      expect(
          () => MlKem768PureDartAlgo.instance.decapsulate(priv, badCt),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('ML-KEM-768 ciphertext'))));
    });

    test('decapsulate throws ArgumentError for a wrong-length secret key',
        () async {
      // secretKey length is checked before ciphertext is touched, so a
      // same-length dummy ciphertext suffices — no real encapsulate() needed.
      final Uint8List badSecretKey = Uint8List(2399);
      final Uint8List ct = Uint8List(MlKem768Sizes.ciphertextBytes);

      expect(
          () => MlKem768PureDartAlgo.instance.decapsulate(badSecretKey, ct),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, 'message', contains('ML-KEM-768 secret key'))));
    });
  });
}
