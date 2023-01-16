import 'package:at_client/src/util/encryption_util.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

void main() {
  group('A group of encryption util tests', () {
    test('generate aes key test', () {
      var aesKey = EncryptionUtil.generateAESKey();
      expect(aesKey, isNotEmpty);
    });

    test('value encrypt/decrypt using aes key', () {
      var aesKey = EncryptionUtil.generateAESKey();
      var valueToEncrypt = 'alice@atsign.com';
      var encryptedValue = EncryptionUtil.encryptValue(valueToEncrypt, aesKey);
      var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, aesKey);
      expect(decryptedValue, valueToEncrypt);
    });

    test('aes key encrypt/decrypt test', () {
      var aesKey = EncryptionUtil.generateAESKey();
      var rsaKeyPair = RSAKeypair.fromRandom();
      var encryptedKey =
          EncryptionUtil.encryptKey(aesKey, rsaKeyPair.publicKey.toString());
      // ignore: deprecated_member_use_from_same_package
      var decryptedKey = EncryptionUtil.decryptKey(
          encryptedKey, rsaKeyPair.privateKey.toString());
      expect(decryptedKey, aesKey);
    });
  });
}
