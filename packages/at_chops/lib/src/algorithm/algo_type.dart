// ignore: constant_identifier_names
import 'package:at_commons/at_commons.dart';

enum SigningAlgoType { ecc_secp256r1, rsa2048, rsa4096 }

enum HashingAlgoType {
  sha256,
  sha512,
  md5,
  argon2id;

  static HashingAlgoType fromString(String name) {
    switch (name.toLowerCase()) {
      case 'sha256':
        return HashingAlgoType.sha256;
      case 'sha512':
        return HashingAlgoType.sha512;
      case 'md5':
        return HashingAlgoType.md5;
      case 'argon2id':
        return HashingAlgoType.argon2id;
      default:
        throw AtException('Invalid hashing algo type');
    }
  }
}
