import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  final keyBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  final plain = Uint8List.fromList(utf8.encode('hello, alice'));

  group('AesGcm256EncryptionAlgo.fromKeyBytes', () {
    test('round trip returns the plaintext', () async {
      final algo = AesGcm256EncryptionAlgo.fromKeyBytes(keyBytes);
      final iv = InitialisationVector.random(12);

      final encrypted = await algo.encrypt(plain, iv: iv);
      final decrypted = await algo.decrypt(encrypted, iv: iv);

      expect(decrypted, plain);
    });

    test('matches the AESKey constructor and interoperates both ways',
        () async {
      final fromBytes = AesGcm256EncryptionAlgo.fromKeyBytes(keyBytes);
      final fromAesKey =
          AesGcm256EncryptionAlgo(AESKey(base64Encode(keyBytes)));
      final iv = InitialisationVector.random(12);

      final ctBytes = await fromBytes.encrypt(plain, iv: iv);
      final ctAesKey = await fromAesKey.encrypt(plain, iv: iv);

      expect(ctBytes, ctAesKey);
      expect(await fromAesKey.decrypt(ctBytes, iv: iv), plain);
      expect(await fromBytes.decrypt(ctAesKey, iv: iv), plain);
    });

    test(
        'zeroing the caller buffer after construction does not affect the algo',
        () async {
      final caller = Uint8List.fromList(keyBytes);
      final algo = AesGcm256EncryptionAlgo.fromKeyBytes(caller);
      final iv = InitialisationVector.random(12);
      final encrypted = await algo.encrypt(plain, iv: iv);

      caller.fillRange(0, caller.length, 0);

      expect(await algo.decrypt(encrypted, iv: iv), plain);
      final reference = AesGcm256EncryptionAlgo.fromKeyBytes(keyBytes);
      expect(await reference.decrypt(encrypted, iv: iv), plain);
    });

    test('a key that is not 32 bytes is rejected', () {
      for (final length in [16, 33]) {
        expect(() => AesGcm256EncryptionAlgo.fromKeyBytes(Uint8List(length)),
            throwsA(isA<AtEncryptionException>()),
            reason: '$length-byte key');
      }
    });

    test('a flipped ciphertext byte makes decrypt throw', () async {
      final algo = AesGcm256EncryptionAlgo.fromKeyBytes(keyBytes);
      final iv = InitialisationVector.random(12);
      final encrypted = await algo.encrypt(plain, iv: iv);

      final tampered = Uint8List.fromList(encrypted);
      tampered[0] ^= 0x01;

      await expectLater(algo.decrypt(tampered, iv: iv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('close zeroes the kept copy and the algo then refuses to run',
        () async {
      final algo = AesGcm256EncryptionAlgo.fromKeyBytes(keyBytes);
      final iv = InitialisationVector.random(12);
      final encrypted = await algo.encrypt(plain, iv: iv);

      algo.close();

      await expectLater(algo.decrypt(encrypted, iv: iv), throwsStateError);
      await expectLater(algo.encrypt(plain, iv: iv), throwsStateError);
    });
  });
}
