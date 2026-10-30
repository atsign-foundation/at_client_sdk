import 'dart:convert';
import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/algorithm/encryption/aes_ctr_factory.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group(
      'A group of tests to verify AES encryption decryption with different key lengths',
      () {
    test('Test encryption and decryption for 128 bit AES key', () async {
      var data = 'Hello World🛠';
      var aesKey = AESKey.generate(16);
      var iv = InitialisationVector.random(16);
      final betterCryptoAESAlgo = AESEncryptionAlgo(aesKey);
      var encryptedBytes =
          await betterCryptoAESAlgo.encrypt(utf8.encode(data), iv: iv);
      var decryptedBytes =
          await betterCryptoAESAlgo.decrypt(encryptedBytes, iv: iv);
      expect(utf8.decode(decryptedBytes), data);
    });
    test('Test encryption and decryption for 192 bit AES key', () async {
      var data = 'Hello\nWorld🛠\n123asdasd!@&^';
      var aesKey = AESKey.generate(24);
      var iv = InitialisationVector.random(16);
      final betterCryptoAESAlgo = AESEncryptionAlgo(aesKey);
      var encryptedBytes =
          await betterCryptoAESAlgo.encrypt(utf8.encode(data), iv: iv);
      var decryptedBytes =
          await betterCryptoAESAlgo.decrypt(encryptedBytes, iv: iv);
      expect(utf8.decode(decryptedBytes), data);
    });
    test('Test encryption and decryption for 256 bit AES key', () async {
      var data = '🛠Hello\nWorld🛠\n123asdasd!@&^\'🛠';
      var aesKey = AESKey.generate(32);
      var iv = InitialisationVector.random(16);
      final betterCryptoAESAlgo = AESEncryptionAlgo(aesKey);
      var encryptedBytes =
          await betterCryptoAESAlgo.encrypt(utf8.encode(data), iv: iv);
      var decryptedBytes =
          await betterCryptoAESAlgo.decrypt(encryptedBytes, iv: iv);
      expect(utf8.decode(decryptedBytes), data);
    });

    test('a key that is not 16/24/32 bytes throws AtEncryptionException',
        () async {
      final aesKey = AESKey.generate(20);
      final algo = AESEncryptionAlgo(aesKey);
      final iv = InitialisationVector.random(16);
      await expectLater(algo.encrypt(utf8.encode('secret'), iv: iv),
          throwsA(isA<AtEncryptionException>()));
    });

    // "From the bad old days when we weren't setting IVs" (aes.dart):
    // an omitted IV silently falls back to 16 zero bytes on both ends,
    // rather than failing loudly. Pinned so a refactor can't drop it
    // unnoticed — callers still relying on this fallback exist.
    test('omitting the IV round-trips via the zero-IV fallback', () async {
      var data = 'no iv supplied';
      var aesKey = AESKey.generate(32);
      final betterCryptoAESAlgo = AESEncryptionAlgo(aesKey);
      var encryptedBytes = await betterCryptoAESAlgo.encrypt(utf8.encode(data));
      var decryptedBytes = await betterCryptoAESAlgo.decrypt(encryptedBytes);
      expect(utf8.decode(decryptedBytes), data);
    });
  });

  group('AesCtrFactory', () {
    test('selects the variant matching the key length', () {
      expect(
          AesCtrFactory.createEncryptionAlgo(AESKey.generate(16))
              .secretKeyLength,
          16);
      expect(
          AesCtrFactory.createEncryptionAlgo(AESKey.generate(24))
              .secretKeyLength,
          24);
      expect(
          AesCtrFactory.createEncryptionAlgo(AESKey.generate(32))
              .secretKeyLength,
          32);
    });

    test('an invalid key length throws AtEncryptionException', () {
      for (final len in [8, 15, 20, 33]) {
        expect(() => AesCtrFactory.createEncryptionAlgo(AESKey.generate(len)),
            throwsA(isA<AtEncryptionException>()),
            reason: '$len-byte key was accepted');
      }
    });
  });
}
