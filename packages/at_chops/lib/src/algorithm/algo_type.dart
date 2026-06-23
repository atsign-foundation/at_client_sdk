// ignore: constant_identifier_names
import 'package:at_commons/at_commons.dart';

// ignore: constant_identifier_names
enum SigningAlgoType {
  ecc_secp256r1,
  rsa2048,
  rsa4096,
  ed25519,
  mldsa65,
}

enum HashingAlgoType {
  sha256,
  sha512,
  md5,
  argon2id;

  static HashingAlgoType fromString(String name) {
    return HashingAlgoType.values.firstWhere(
        (algo) => algo.name == name.toLowerCase(),
        orElse: () => throw AtException('Invalid hashing algo type'));
  }
}
