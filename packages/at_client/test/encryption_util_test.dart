import 'package:at_client/src/util/encryption_util.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

bool wrappedDecryptSucceeds(
    {required String cipherText,
    required String aesKey,
    required String? ivBase64,
    required String clearText}) {
  try {
    var deciphered =
        EncryptionUtil.decryptValue(cipherText, aesKey, ivBase64: ivBase64);
    if (deciphered != clearText) {
      return false;
    } else {
      return true;
    }
  } catch (e) {
    return false;
  }
}

void main() {
  group('A group of encryption util tests', () {
    test('generate aes key test', () {
      var aesKey = EncryptionUtil.generateAESKey();
      expect(aesKey, isNotEmpty);
    });

    test('legacy encrypt/decrypt with AES', () {
      var aesKey = EncryptionUtil.generateAESKey();
      var valueToEncrypt = 'alice@atsign.com';
      var encryptedValue = EncryptionUtil.encryptValue(valueToEncrypt, aesKey);
      var decryptedValue = EncryptionUtil.decryptValue(encryptedValue, aesKey);
      expect(decryptedValue, valueToEncrypt);
    });

    test('encrypt/decrypt with AES', () {
      var aesKey = EncryptionUtil.generateAESKey();
      var iv = EncryptionUtil.generateIV();
      var valueToEncrypt = 'alice@atsign.com';
      var encryptedValue =
          EncryptionUtil.encryptValue(valueToEncrypt, aesKey, ivBase64: iv);
      var decryptedValue =
          EncryptionUtil.decryptValue(encryptedValue, aesKey, ivBase64: iv);
      expect(decryptedValue, valueToEncrypt);

      expect(
          wrappedDecryptSucceeds(
              cipherText: encryptedValue,
              aesKey: aesKey,
              ivBase64: null,
              clearText: valueToEncrypt),
          false);

      for (int i = 0; i < 10; i++) {
        var otherIV = EncryptionUtil.generateIV();
        expect(
            wrappedDecryptSucceeds(
                cipherText: encryptedValue,
                aesKey: aesKey,
                ivBase64: otherIV,
                clearText: valueToEncrypt),
            false);
      }
    });

    test('RSA encrypt/decrypt test', () {
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
