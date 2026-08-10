// ignore: constant_identifier_names
import 'package:at_commons/at_commons.dart';

/// Every constant here is spelled all-lowercase so that its [name] is itself
/// the identifier an algorithm reports and a downstream protocol keys on —
/// there is no second, camelCase vocabulary to translate between.
enum SigningAlgoType {
  eccSecp256r1,
  rsa2048,
  rsa4096,
  ed25519,
  mldsa65;

  static SigningAlgoType fromString(String name) {
    return SigningAlgoType.values.firstWhere(
        (algo) => algo.name.toLowerCase() == name.toLowerCase(),
        orElse: () => throw AtException('Invalid signing algo type: $name'));
  }
}

enum HashingAlgoType {
  sha256,
  sha512,
  md5,
  argon2id;

  static HashingAlgoType fromString(String name) {
    return HashingAlgoType.values.firstWhere(
        (algo) => algo.name.toLowerCase() == name.toLowerCase(),
        orElse: () => throw AtException('Invalid hashing algo type'));
  }
}

/// Algorithms that encrypt and decrypt data, symmetric ([aesctr],
/// [aesgcm256]) and asymmetric ([rsa]) alike.
///
/// A Key Encapsulation Mechanism does not encrypt data, so it lives in
/// [KemAlgoType] rather than here.
enum EncryptionAlgoType {
  aesctr,
  aesgcm256,
  rsa;

  static EncryptionAlgoType fromString(String name) {
    return EncryptionAlgoType.values.firstWhere(
        (algo) => algo.name.toLowerCase() == name.toLowerCase(),
        orElse: () => throw AtException('Invalid encryption algo type: $name'));
  }
}

/// Key Encapsulation Mechanisms — they derive a shared secret rather than
/// encrypting caller-supplied data, which is why they are not in
/// [EncryptionAlgoType].
enum KemAlgoType {
  mlkem768,
  xwing;

  static KemAlgoType fromString(String name) {
    return KemAlgoType.values.firstWhere(
        (algo) => algo.name.toLowerCase() == name.toLowerCase(),
        orElse: () => throw AtException('Invalid KEM algo type: $name'));
  }
}

/// Diffie–Hellman key agreement primitives — they derive a shared secret from
/// two key pairs, encrypting nothing themselves.
enum KeyAgreementAlgoType {
  x25519;

  static KeyAgreementAlgoType fromString(String name) {
    return KeyAgreementAlgoType.values.firstWhere(
        (algo) => algo.name.toLowerCase() == name.toLowerCase(),
        orElse: () =>
            throw AtException('Invalid key agreement algo type: $name'));
  }
}
