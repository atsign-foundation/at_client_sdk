import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/ml_dsa_65_pure_dart_algo.dart';
import 'package:at_chops/src/algorithm/ml_kem_768_pure_dart_algo.dart';
import 'package:at_chops/src/algorithm/x25519_pure_dart_algo.dart';
import 'package:at_chops/src/key/at_key_pair.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_chops/src/key/impl/at_encryption_key_pair.dart';
import 'package:at_chops/src/key/impl/at_ml_dsa_65_key_pair.dart';
import 'package:at_chops/src/key/impl/at_ml_kem_768_key_pair.dart';
import 'package:at_chops/src/key/impl/at_pkam_key_pair.dart';
import 'package:at_chops/src/key/impl/at_x25519_key_pair.dart';
import 'package:at_chops/src/key/key_type.dart';
import 'package:better_cryptography/better_cryptography.dart';
import 'package:crypton/crypton.dart';
import 'package:encrypt/encrypt.dart';

class AtChopsUtil {
  /// Generates a random initialisation vector from a given length
  /// Length must be 0 to 16
  static InitialisationVector generateRandomIV(int length) {
    final iv = IV.fromSecureRandom(length);
    return InitialisationVector(iv.bytes);
  }

  static InitialisationVector generateIVLegacy() {
    return InitialisationVector(IV(Uint8List(16)).bytes);
  }

  static InitialisationVector generateIVFromBase64String(String ivBase64) {
    final iv = IV.fromBase64(ivBase64);
    return InitialisationVector(iv.bytes);
  }

  /// Generates RSA keypair with default size 2048 bits
  static RSAKeypair generateRSAKeyPair({int keySize = 2048}) {
    return RSAKeypair.fromRandom(keySize: keySize);
  }

  /// Generates AtEncryption asymmetric keypair with default size 2048 bits
  static AtEncryptionKeyPair generateAtEncryptionKeyPair({int keySize = 2048}) {
    final rsaKeyPair = RSAKeypair.fromRandom(keySize: keySize);
    return AtEncryptionKeyPair.create(
        rsaKeyPair.publicKey.toString(), rsaKeyPair.privateKey.toString());
  }

  /// Generates AtEncryption asymmetric keypair with default size 2048 bits
  static AtPkamKeyPair generateAtPkamKeyPair({int keySize = 2048}) {
    final rsaKeyPair = RSAKeypair.fromRandom(keySize: keySize);
    return AtPkamKeyPair.create(
        rsaKeyPair.publicKey.toString(), rsaKeyPair.privateKey.toString());
  }

  /// Generates EC keypair
  static ECKeypair generateECKeyPair() {
    return ECKeypair.fromRandom();
  }

  /// Generates an symmetric keypair for ED25519 elliptic curve signing and verification
  static Future<SimpleKeyPair> generateEd25519KeyPair() async {
    return await Ed25519().newKeyPair();
  }

  /// Generates an X25519 key pair for Diffie–Hellman key agreement.
  ///
  /// Backed by the pure-Dart X25519 implementation (via `package:cryptography`).
  /// Raw 32-byte public and private keys are base64-encoded so they fit the
  /// existing String-typed key contract.
  static Future<AtX25519KeyPair> generateX25519KeyPair() async {
    final (publicKey: Uint8List pub, privateKey: Uint8List priv) =
        await X25519PureDartAlgo.instance.generateKeyPair();
    return AtX25519KeyPair.create(base64Encode(pub), base64Encode(priv));
  }

  /// Generates an ML-KEM-768 key pair for post-quantum key encapsulation.
  ///
  /// Backed by the pure-Dart ML-KEM-768 implementation (via `package:pqcrypto`).
  /// Raw 1184-byte public key and 2400-byte secret key are base64-encoded.
  /// Persisted ML-KEM keys must always be used with the pure-Dart algorithm
  /// — the FFI backend returns opaque process-lifetime handles instead of
  /// real bytes.
  static Future<AtMlKem768KeyPair> generateMlKem768KeyPair() async {
    final (publicKey: Uint8List pub, secretKey: Uint8List sk) =
        await MlKem768PureDartAlgo.instance.generateKeyPair();
    return AtMlKem768KeyPair.create(base64Encode(pub), base64Encode(sk));
  }

  /// Generates an ML-DSA-65 key pair for post-quantum digital signatures.
  ///
  /// Backed by the pure-Dart ML-DSA-65 implementation (via `package:pqcrypto`).
  /// Raw 1952-byte public key and 4032-byte secret key are base64-encoded.
  /// Both keys are serializable and interoperable with the FFI backend.
  static Future<AtMlDsa65KeyPair> generateMlDsa65KeyPair() async {
    final (publicKey: Uint8List pub, secretKey: Uint8List sk) =
        await MlDsa65PureDartAlgo.generateKeyPair();
    return AtMlDsa65KeyPair.create(base64Encode(pub), base64Encode(sk));
  }

  /// Generates symmetric AES key based on [keyType]
  static SymmetricKey generateSymmetricKey(EncryptionKeyType keyType) {
    switch (keyType) {
      case EncryptionKeyType.aes128:
        return AESKey.generate(16);
      case EncryptionKeyType.aes192:
        return AESKey.generate(24);
      case EncryptionKeyType.aes256:
        return AESKey.generate(32);
      default:
        return AESKey.generate(32);
    }
  }
}
