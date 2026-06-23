import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_chops/src/key/impl/ed25519_key.dart';
import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for AES Key generation', () {
    test('Test generate AESKey - 128 bit', () {
      final aesKey = AESKey.generate(16);
      expect(Key.fromBase64(aesKey.key).length, 16);
    });
    test('Test generate AESKey - 128 bit random generation', () {
      final aesKey_1 = AESKey.generate(16);
      final aesKey_2 = AESKey.generate(16);
      expect(aesKey_1, isNot(aesKey_2));
    });
    test('Test generate AESKey - 256 bit', () {
      final aesKey = AESKey.generate(32);
      expect(Key.fromBase64(aesKey.key).length, 32);
    });
    test('Test generate AESKey - 256 bit random generation', () {
      final aesKey_1 = AESKey.generate(32);
      final aesKey_2 = AESKey.generate(32);
      expect(aesKey_1, isNot(aesKey_2));
    });
    test('check random key generated length for 128 bit key', () {
      final aesKey = AESKey.generate(16);
      expect(aesKey.getLength(), 16);
    });
    test('check random key generated  length for 192 bit key', () {
      final aesKey = AESKey.generate(24);
      expect(aesKey.getLength(), 24);
    });
    test('check random key generated  length for 256 bit key', () {
      final aesKey = AESKey.generate(32);
      expect(aesKey.getLength(), 32);
    });
    test('verify key length for 256 bit key constructed from string', () {
      final aesKey_1 = AESKey.generate(32);
      final aesKey = AESKey(aesKey_1.key);
      expect(aesKey.getLength(), 32);
    });
    test('verify key length for 192 bit key constructed from string', () {
      final aesKey_1 = AESKey.generate(24);
      final aesKey = AESKey(aesKey_1.key);
      expect(aesKey.getLength(), 24);
    });
    test('verify key length for 128 bit key constructed from string', () {
      final aesKey_1 = AESKey.generate(16);
      final aesKey = AESKey(aesKey_1.key);
      expect(aesKey.getLength(), 16);
    });
  });

  group('A group of tests for other key generation functions', () {
    test('Test generate Ed25519Key', () {
      final ed25519Key = Ed25519Key.generate(32);
      expect(ed25519Key.getLength(), 32);
    });

    test('Test generate Ed25519Key random generation', () {
      final ed25519Key1 = Ed25519Key.generate(32);
      final ed25519Key2 = Ed25519Key.generate(32);
      expect(ed25519Key1.key, isNot(ed25519Key2.key));
    });

    test('Test generate RSA key pair', () {
      final rsaKeyPair = RsaKeyPair.generate();
      expect(rsaKeyPair.atPublicKey.publicKey, isNotEmpty);
      expect(rsaKeyPair.atPrivateKey.privateKey, isNotEmpty);
    });

    test('Test generate RSA key pair random generation', () {
      final rsaKeyPair1 = RsaKeyPair.generate();
      final rsaKeyPair2 = RsaKeyPair.generate();

      expect(
        rsaKeyPair1.atPublicKey.publicKey,
        isNot(rsaKeyPair2.atPublicKey.publicKey),
      );
      expect(
        rsaKeyPair1.atPrivateKey.privateKey,
        isNot(rsaKeyPair2.atPrivateKey.privateKey),
      );
    });

    test('Test generate X25519 key pair', () async {
      final x25519KeyPair = await X25519KeyPair.generate();
      expect(base64Decode(x25519KeyPair.atPublicKey.publicKey).length, 32);
      expect(base64Decode(x25519KeyPair.atPrivateKey.privateKey).length, 32);
    });

    test('Test generate X25519 key pair random generation', () async {
      final x25519KeyPair1 = await X25519KeyPair.generate();
      final x25519KeyPair2 = await X25519KeyPair.generate();

      expect(
        x25519KeyPair1.atPublicKey.publicKey,
        isNot(x25519KeyPair2.atPublicKey.publicKey),
      );
      expect(
        x25519KeyPair1.atPrivateKey.privateKey,
        isNot(x25519KeyPair2.atPrivateKey.privateKey),
      );
    });

    test('Test generate ML-KEM-768 key pair', () async {
      final mlKem768KeyPair = await MlKem768KeyPair.generate();
      expect(base64Decode(mlKem768KeyPair.atPublicKey.publicKey).length, 1184);
      expect(
        base64Decode(mlKem768KeyPair.atPrivateKey.privateKey).length,
        2400,
      );
    });

    test('Test generate ML-KEM-768 key pair random generation', () async {
      final mlKem768KeyPair1 = await MlKem768KeyPair.generate();
      final mlKem768KeyPair2 = await MlKem768KeyPair.generate();

      expect(
        mlKem768KeyPair1.atPublicKey.publicKey,
        isNot(mlKem768KeyPair2.atPublicKey.publicKey),
      );
      expect(
        mlKem768KeyPair1.atPrivateKey.privateKey,
        isNot(mlKem768KeyPair2.atPrivateKey.privateKey),
      );
    });

    test('Test generate ML-DSA-65 key pair', () async {
      final mlDsa65KeyPair = await MlDsa65KeyPair.generate();
      expect(base64Decode(mlDsa65KeyPair.atPublicKey.publicKey).length, 1952);
      expect(
        base64Decode(mlDsa65KeyPair.atPrivateKey.privateKey).length,
        4032,
      );
    });

    test('Test generate ML-DSA-65 key pair random generation', () async {
      final mlDsa65KeyPair1 = await MlDsa65KeyPair.generate();
      final mlDsa65KeyPair2 = await MlDsa65KeyPair.generate();

      expect(
        mlDsa65KeyPair1.atPublicKey.publicKey,
        isNot(mlDsa65KeyPair2.atPublicKey.publicKey),
      );
      expect(
        mlDsa65KeyPair1.atPrivateKey.privateKey,
        isNot(mlDsa65KeyPair2.atPrivateKey.privateKey),
      );
    });

    test('Test generate X-Wing key pair', () async {
      final xWingKeyPair = await XWingKeyPair.generate();
      expect(base64Decode(xWingKeyPair.atPublicKey.publicKey).length, 1216);
      expect(base64Decode(xWingKeyPair.atPrivateKey.privateKey).length, 32);
    });

    test('Test generate X-Wing key pair random generation', () async {
      final xWingKeyPair1 = await XWingKeyPair.generate();
      final xWingKeyPair2 = await XWingKeyPair.generate();

      expect(
        xWingKeyPair1.atPublicKey.publicKey,
        isNot(xWingKeyPair2.atPublicKey.publicKey),
      );
      expect(
        xWingKeyPair1.atPrivateKey.privateKey,
        isNot(xWingKeyPair2.atPrivateKey.privateKey),
      );
    });
  });
}
