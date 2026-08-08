import 'package:at_commons/at_commons.dart';

enum SigningAlgoType {
  // Not lowerCamelCase on purpose, and the ignore has to sit on this line
  // rather than on the enum: the MEMBER NAME is the wire literal. It is what
  // `pkam:signingAlgo:ecc_secp256r1:hashingAlgo:sha256:...` carries, so
  // renaming it to `eccSecp256r1` would change the protocol, not the style.
  // ignore: constant_identifier_names
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
