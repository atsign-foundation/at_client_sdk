import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/encryption/ml_kem_768_validation.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 pure-Dart', () {
    test('encapsulate/decapsulate round-trip yields matching shared secrets',
        () async {
      final MlKem768KeyPair kp = await MlKem768KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlKem768PureDartAlgo.instance;
      final enc = await algo.encapsulate(pub);
      final Uint8List recovered = await algo.decapsulate(priv, enc.ciphertext);

      expect(recovered, equals(enc.sharedSecret));
      expect(enc.sharedSecret.length, equals(32));
    });

    test('Generated key pair has FIPS 203 key sizes', () async {
      final MlKem768KeyPair kp = await MlKem768KeyPair.generate();
      expect(base64Decode(kp.atPublicKey.publicKey).length, equals(1184));
      expect(base64Decode(kp.atPrivateKey.privateKey).length, equals(2400));
    });

    test(
        'Decapsulating tampered ciphertext does not throw and (per FIPS 203)'
        ' returns an implicit-rejection secret different from the real one',
        () async {
      final MlKem768KeyPair kp = await MlKem768KeyPair.generate();
      final Uint8List pub = base64Decode(kp.atPublicKey.publicKey);
      final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);

      final algo = MlKem768PureDartAlgo.instance;
      final enc = await algo.encapsulate(pub);

      final Uint8List tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0x01;

      final Uint8List bad = await algo.decapsulate(priv, tampered);
      expect(bad, isNot(equals(enc.sharedSecret)));
      expect(bad.length, equals(32));
    });

    test('encapsulate throws ArgumentError for a wrong-length public key',
        () async {
      final Uint8List badPub = Uint8List(MlKem768Sizes.publicKeyBytes - 1);
      expect(() => MlKem768PureDartAlgo.instance.encapsulate(badPub),
          throwsA(isA<ArgumentError>()));
    });

    test('decapsulate throws ArgumentError for a wrong-length ciphertext',
        () async {
      final MlKem768KeyPair kp = await MlKem768KeyPair.generate();
      final Uint8List priv = base64Decode(kp.atPrivateKey.privateKey);
      final Uint8List badCt = Uint8List(MlKem768Sizes.ciphertextBytes + 1);

      expect(() => MlKem768PureDartAlgo.instance.decapsulate(priv, badCt),
          throwsA(isA<ArgumentError>()));
    });
  });
}
