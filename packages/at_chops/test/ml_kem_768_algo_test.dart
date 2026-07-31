import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
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
  });
}
