import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/keys.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_chops/src/key/impl/at_encryption_key_pair.dart';
import 'package:at_chops/src/key/impl/at_pkam_key_pair.dart';
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
