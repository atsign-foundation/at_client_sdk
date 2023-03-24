import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

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
          () => EncryptionUtil.decryptValue(encryptedValue, aesKey),
          throwsA(predicate((e) =>
              e is AtKeyException &&
              e.message ==
                  'Invalid argument(s): Invalid or corrupted pad block')));

      for (int i = 0; i < 10; i++) {
        var otherIV = EncryptionUtil.generateIV();
        expect(
            () => EncryptionUtil.decryptValue(encryptedValue, aesKey,
                ivBase64: otherIV),
            throwsA(predicate((e) =>
                e is AtKeyException &&
                e.message ==
                    'Invalid argument(s): Invalid or corrupted pad block')));
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
