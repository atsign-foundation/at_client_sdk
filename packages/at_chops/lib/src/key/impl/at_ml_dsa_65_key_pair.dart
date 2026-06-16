import 'package:at_chops/src/key/keys.dart';

/// ML-DSA-65 (FIPS 204) signing key pair.
///
/// Both keys are stored as base64-encoded raw bytes:
/// - Public key: 1952 bytes
/// - Secret key: 4032 bytes
class AtMlDsa65KeyPair extends AsymmetricKeyPair {
  AtMlDsa65KeyPair.create(super.publicKey, super.privateKey) : super.create();
}
