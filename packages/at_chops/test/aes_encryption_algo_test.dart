import 'dart:convert';
import 'package:at_chops/at_chops.dart';
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
  });
}
