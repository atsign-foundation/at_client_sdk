import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group(
      'A group of tests for encryption/decryption by passing public/private key',
      () {
    test('Test asymmetric encryption/decryption using rsa 2048', () {
      var defaultEncryptionAlgo = RsaEncryptionAlgo();
      var rsa2048KeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
      var rsaPublicKey = rsa2048KeyPair.atPublicKey;
      var dataToEncrypt = 'Hello World12!@';
      defaultEncryptionAlgo.atPublicKey = rsaPublicKey;
      var encryptedData =
          defaultEncryptionAlgo.encrypt(utf8.encode(dataToEncrypt));
      var rsaPrivateKey = rsa2048KeyPair.atPrivateKey;
      defaultEncryptionAlgo.atPrivateKey = rsaPrivateKey;
      var decryptedData = defaultEncryptionAlgo.decrypt(encryptedData);
      expect(utf8.decode(decryptedData), dataToEncrypt);
    });
    test('Test asymmetric encryption/decryption using rsa 4096', () {
      var defaultEncryptionAlgo = RsaEncryptionAlgo();
      var rsa2048KeyPair =
          AtChopsUtil.generateAtEncryptionKeyPair(keySize: 4096);
      var rsaPublicKey = rsa2048KeyPair.atPublicKey;
      var dataToEncrypt = 'Hello World12!@';
      defaultEncryptionAlgo.atPublicKey = rsaPublicKey;
      var encryptedData =
          defaultEncryptionAlgo.encrypt(utf8.encode(dataToEncrypt));
      var rsaPrivateKey = rsa2048KeyPair.atPrivateKey;
      defaultEncryptionAlgo.atPrivateKey = rsaPrivateKey;
      var decryptedData = defaultEncryptionAlgo.decrypt(encryptedData);
      expect(utf8.decode(decryptedData), dataToEncrypt);
    });
    test('Test encrypt throws exception when passed public key is null', () {
      var defaultEncryptionAlgo = RsaEncryptionAlgo();
      var dataToEncrypt = 'Hello World12!@';
      AtPublicKey? publicKey;
      defaultEncryptionAlgo.atPublicKey = publicKey;
      expect(
          () => defaultEncryptionAlgo.encrypt(utf8.encode(dataToEncrypt)),
          throwsA(predicate((e) =>
              e is AtEncryptionException &&
              e.toString().contains('EncryptionKeypair/public key not set'))));
    });
    test('Test decrypt throws exception when passed private key is null', () {
      var defaultEncryptionAlgo = RsaEncryptionAlgo();
      var encryptedData = 'random data';
      AtPrivateKey? privateKey;
      defaultEncryptionAlgo.atPrivateKey = privateKey;
      expect(
          () => defaultEncryptionAlgo.decrypt(utf8.encode(encryptedData)),
          throwsA(predicate((e) =>
              e is AtDecryptionException &&
              e.toString().contains('EncryptionKeypair/public key not set'))));
    });
  });

  group(
      'A group of tests for encryption/decryption by setting encryption key pair',
      () {
    test('Test asymmetric encryption/decryption using rsa 2048 key pair', () {
      var rsa2048KeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
      var defaultEncryptionAlgo = RsaEncryptionAlgo.fromKeyPair(rsa2048KeyPair);
      var dataToEncrypt = 'Hello World12!@';
      var encryptedData =
          defaultEncryptionAlgo.encrypt(utf8.encode(dataToEncrypt));
      var decryptedData = defaultEncryptionAlgo.decrypt(encryptedData);
      expect(utf8.decode(decryptedData), dataToEncrypt);
    });
    test('Test asymmetric encryption/decryption using rsa 4096 key pair', () {
      var rsa2048KeyPair =
          AtChopsUtil.generateAtEncryptionKeyPair(keySize: 4096);
      var defaultEncryptionAlgo = RsaEncryptionAlgo.fromKeyPair(rsa2048KeyPair);
      var dataToEncrypt = 'Hello World12!@';
      var encryptedData =
          defaultEncryptionAlgo.encrypt(utf8.encode(dataToEncrypt));
      var decryptedData = defaultEncryptionAlgo.decrypt(encryptedData);
      expect(utf8.decode(decryptedData), dataToEncrypt);
    });
    test('Test encrypt throws exception when encryption keypair is null', () {
      var defaultEncryptionAlgo = RsaEncryptionAlgo.fromKeyPair(null);
      var dataToEncrypt = 'Hello World12!@';
      expect(
          () => defaultEncryptionAlgo.encrypt(utf8.encode(dataToEncrypt)),
          throwsA(predicate((e) =>
              e is AtEncryptionException &&
              e.toString().contains('EncryptionKeypair/public key not set'))));
    });
    test('Test decrypt throws exception when encryption keypair is null', () {
      var defaultEncryptionAlgo = RsaEncryptionAlgo.fromKeyPair(null);
      var encryptedData = 'random data';
      expect(
          () => defaultEncryptionAlgo.decrypt(utf8.encode(encryptedData)),
          throwsA(predicate((e) =>
              e is AtDecryptionException &&
              e.toString().contains('EncryptionKeypair/public key not set'))));
    });
  });
}
