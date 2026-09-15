import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

// Tests to verify that what EncryptionUtil encrypts, at_chops' algorithm
// classes decrypt, and vice versa.
void main() {
  test(
      'A test to verify encrypting AES key with encryption util and decryption with at_chops',
      () async {
    // Generate RSA key pair. Generate AES key. Encrypt AES key using RSA public key using EncryptionUtil method
    // Decrypt encryptedAESKey with the RSA algorithm class (uses RSA private key)
    var encryptionKeyPair = RsaKeyPair.generate();
    var encryptionPublicKey = encryptionKeyPair.atPublicKey.publicKey;
    var aesKey = EncryptionUtil.generateAESKey();
    var encryptedAesKey =
        EncryptionUtil.encryptKey(aesKey, encryptionPublicKey);
    var decryptedAesKey = utf8.decode(
        RsaEncryptionAlgo.fromKeyPair(encryptionKeyPair)
            .decrypt(base64Decode(encryptedAesKey)));
    expect(decryptedAesKey, aesKey);
  });
  test(
      'A test to verify encrypting AES key with at_chops and decryption with EncryptionUtil',
      () async {
    // Generate RSA key pair. Generate AES key. Encrypt AES key with the RSA algorithm class (uses RSA public key)
    // Decrypt encryptedAESKey with EncryptionUtil using RSA private key
    var encryptionKeyPair = RsaKeyPair.generate();
    var encryptionPrivateKey = encryptionKeyPair.atPrivateKey.privateKey;
    var aesKey = AESKey.generate(32).key;

    var encryptedAesKey = base64Encode(
        RsaEncryptionAlgo.fromKeyPair(encryptionKeyPair)
            .encrypt(utf8.encode(aesKey)));

    var decryptedAesKey =
        //ignore: deprecated_member_use_from_same_package
        EncryptionUtil.decryptKey(encryptedAesKey, encryptionPrivateKey);
    expect(decryptedAesKey, aesKey);
  });

  test(
      'A test to verify data encryption with encryption util and decryption with at_chops',
      () async {
    // Generate AES key. Encrypt data with EncryptionUtil using AES key
    // Decrypt the encrypted value with the AES algorithm class under the legacy IV
    var aesKey = EncryptionUtil.generateAESKey();
    var dataToEncrypt = 'alice@atsign.com';
    var encryptedData = EncryptionUtil.encryptValue(dataToEncrypt, aesKey);
    var decryptedData = StringAESEncryptor(AESKey(aesKey))
        .decrypt(encryptedData, iv: InitialisationVector.legacy());
    expect(decryptedData, dataToEncrypt);
  });

  test(
      'A test to verify data encryption with at_chops  and decryption with encryption_util',
      () async {
    // Generate AES key. Encrypt data with the AES algorithm class under the legacy IV
    // Decrypt the encrypted value with EncryptionUtil
    var aesKey = AESKey.generate(32);
    var dataToEncrypt = 'alice@atsign.com';
    var encryptedData = StringAESEncryptor(aesKey)
        .encrypt(dataToEncrypt, iv: InitialisationVector.legacy());
    var decryptedData = EncryptionUtil.decryptValue(encryptedData, aesKey.key);
    expect(decryptedData, dataToEncrypt);
  });

  test(
      'A test to verify data(with emoji) encryption with encryption util and decryption with at_chops',
      () async {
    // Generate AES key. Encrypt data with EncryptionUtil using AES key
    // Decrypt the encrypted value with the AES algorithm class under the legacy IV
    var aesKey = EncryptionUtil.generateAESKey();
    var dataToEncrypt = 'alice@🦄🛠';
    var encryptedData = EncryptionUtil.encryptValue(dataToEncrypt, aesKey);
    var decryptedData = StringAESEncryptor(AESKey(aesKey))
        .decrypt(encryptedData, iv: InitialisationVector.legacy());
    expect(decryptedData, dataToEncrypt);
  });

  test(
      'A test to verify data(with emoji) encryption with at_chops  and decryption with encryption_util',
      () async {
    // Generate AES key. Encrypt data with the AES algorithm class under the legacy IV
    // Decrypt the encrypted value with EncryptionUtil
    var aesKey = AESKey.generate(32);
    var dataToEncrypt = 'alice@🦄🛠';
    var encryptedData = StringAESEncryptor(aesKey)
        .encrypt(dataToEncrypt, iv: InitialisationVector.legacy());
    var decryptedData = EncryptionUtil.decryptValue(encryptedData, aesKey.key);
    expect(decryptedData, dataToEncrypt);
  });
}
