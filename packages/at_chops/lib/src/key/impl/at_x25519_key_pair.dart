import 'package:at_chops/src/key/keys.dart';

/// X25519 key pair used for Diffie–Hellman key agreement.
///
/// Both public and private keys are 32-byte raw values encoded as base64
/// strings, so they fit the existing [AsymmetricKeyPair] String contract.
/// Callers consuming the bytes should `base64Decode` at the algorithm
/// boundary.
class AtX25519KeyPair extends AsymmetricKeyPair {
  AtX25519KeyPair.create(super.publicKey, super.privateKey) : super.create();
}
