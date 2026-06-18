import 'dart:convert';
import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';
import 'aes_encrption_old_impl.dart';

void main() {
  group(
      'A group of tests to verify compatibility between old AES algo vs better crypto AES algo',
      () {
    test('Encrypt with old algo and decrypt with better crypto', () async {
      var data = 'Hello World';
      var aesKey = AESKey.generate(32);
      var iv = InitialisationVector.random(16);
      final encryptionAlgo = AESEncryptionAlgoV1(aesKey);
      var encryptedBytes = encryptionAlgo.encrypt(utf8.encode(data), iv: iv);
      var betterCryptoAESAlgo = AESEncryptionAlgo(aesKey);
      var decryptedBytes =
          await betterCryptoAESAlgo.decrypt(encryptedBytes, iv: iv);
      expect(utf8.decode(decryptedBytes), data);
    });
    test('Encrypt with better crypto AES algo and decrypt with old algo',
        () async {
      var data = 'Hello World12345';
      var aesKey = AESKey.generate(32);
      var iv = InitialisationVector.random(16);
      final betterCryptoAESAlgo = AESEncryptionAlgo(aesKey);
      var encryptedBytes =
          await betterCryptoAESAlgo.encrypt(utf8.encode(data), iv: iv);
      var oldAlgo = AESEncryptionAlgoV1(aesKey);
      var decryptedBytes = oldAlgo.decrypt(encryptedBytes, iv: iv);
      expect(utf8.decode(decryptedBytes), data);
    });
  });
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
  });
}
