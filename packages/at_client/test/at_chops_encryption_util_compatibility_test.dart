import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

void main() {
  test(
      'A test to verify encrypting AES key with encryption util and decryption with at_chops',
      () {
    // Generate RSA key pair. Generate AES key. Encrypt AES key using RSA public key using EncryptionUtil method
    // Decrypt encryptedAESKey using AtChops (uses RSA private key)
    var encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    var encryptionPublicKey = encryptionKeyPair.atPublicKey.publicKey;
    var aesKey = EncryptionUtil.generateAESKey();
    var encryptedAesKey =
        EncryptionUtil.encryptKey(aesKey, encryptionPublicKey);
    AtChopsKeys atChopsKeys = AtChopsKeys.create(encryptionKeyPair, null);
    var atChops = AtChopsImpl(atChopsKeys);
    var decryptedAesKey = atChops
        .decryptString(encryptedAesKey, EncryptionKeyType.rsa2048)
        .result;
    expect(decryptedAesKey, aesKey);
  });
  test(
      'A test to verify encrypting AES key with at_chops and decryption with EncryptionUtil',
      () {
    // Generate RSA key pair. Generate AES key. Encrypt AES key using AtChops(uses RSA public key)
    // Decrypt encryptedAESKey with EncryptionUtil using RSA private key
    var encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    var encryptionPrivateKey = encryptionKeyPair.atPrivateKey.privateKey;
    var aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;

    AtChopsKeys atChopsKeys = AtChopsKeys.create(encryptionKeyPair, null);
    var atChops = AtChopsImpl(atChopsKeys);
    var encryptedAesKey =
        atChops.encryptString(aesKey, EncryptionKeyType.rsa2048).result;
    var decryptedAesKey =
        EncryptionUtil.decryptKey(encryptedAesKey, encryptionPrivateKey);
    expect(decryptedAesKey, aesKey);
  });

  test(
      'A test to verify data encryption with encryption util and decryption with at_chops',
      () {
    // Generate AES key. Encrypt data with EncryptionUtil using AES key
    // Create a AESEncryption algo object using AES key and pass it to AtChops. Decrypt the encrypted value with AtChops
    var aesKey = EncryptionUtil.generateAESKey();
    var dataToEncrypt = 'alice@atsign.com';
    var encryptedData = EncryptionUtil.encryptValue(dataToEncrypt, aesKey);
    var encryptionAlgo = AESEncryptionAlgo(AESKey(aesKey));
    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    var atChops = AtChopsImpl(atChopsKeys);
    var decryptedData = atChops
        .decryptString(encryptedData, EncryptionKeyType.aes256,
            encryptionAlgorithm: encryptionAlgo,
            iv: AtChopsUtil.generateIVLegacy())
        .result;
    expect(decryptedData, dataToEncrypt);
  });

  test(
      'A test to verify data encryption with at_chops  and decryption with encryption_util',
      () {
    // Generate AES key. Encrypt data with AtChops using AES key
    // Decrypt the encrypted value with EncryptionUtil
    var aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var dataToEncrypt = 'alice@atsign.com';
    var encryptionAlgo = AESEncryptionAlgo(AESKey(aesKey.key));
    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    var atChops = AtChopsImpl(atChopsKeys);
    var encryptedData = atChops
        .encryptString(dataToEncrypt, EncryptionKeyType.aes256,
            encryptionAlgorithm: encryptionAlgo,
            iv: AtChopsUtil.generateIVLegacy())
        .result;
    var decryptedData = EncryptionUtil.decryptValue(encryptedData, aesKey.key);
    expect(decryptedData, dataToEncrypt);
  });

  test(
      'A test to verify data(with emoji) encryption with encryption util and decryption with at_chops',
      () {
    // Generate AES key. Encrypt data with EncryptionUtil using AES key
    // Create a AESEncryption algo object using AES key and pass it to AtChops. Decrypt the encrypted value with AtChops
    var aesKey = EncryptionUtil.generateAESKey();
    var dataToEncrypt = 'alice@🦄🛠';
    var encryptedData = EncryptionUtil.encryptValue(dataToEncrypt, aesKey);
    var encryptionAlgo = AESEncryptionAlgo(AESKey(aesKey));
    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    var atChops = AtChopsImpl(atChopsKeys);
    var decryptedData = atChops
        .decryptString(encryptedData, EncryptionKeyType.aes256,
            encryptionAlgorithm: encryptionAlgo,
            iv: AtChopsUtil.generateIVLegacy())
        .result;
    expect(decryptedData, dataToEncrypt);
  });

  test(
      'A test to verify data(with emoji) encryption with at_chops  and decryption with encryption_util',
      () {
    // Generate AES key. Encrypt data with AtChops using AES key
    // Decrypt the encrypted value with EncryptionUtil
    var aesKey = AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    var dataToEncrypt = 'alice@🦄🛠';
    var encryptionAlgo = AESEncryptionAlgo(AESKey(aesKey.key));
    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    var atChops = AtChopsImpl(atChopsKeys);
    var encryptedData = atChops
        .encryptString(dataToEncrypt, EncryptionKeyType.aes256,
            encryptionAlgorithm: encryptionAlgo,
            iv: AtChopsUtil.generateIVLegacy())
        .result;
    var decryptedData = EncryptionUtil.decryptValue(encryptedData, aesKey.key);
    expect(decryptedData, dataToEncrypt);
  });
}
