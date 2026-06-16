import 'package:at_chops/src/key/keys.dart';

/// X-Wing hybrid post-quantum/traditional KEM key pair
/// (draft-connolly-cfrg-xwing-kem).
///
/// Public keys are 1216 raw bytes (`pk_ML-KEM-768 || pk_X25519`); the
/// private key is the 32-byte seed from which everything else is re-derived.
/// Both are encoded as base64 strings to fit the existing
/// [AsymmetricKeyPair] String contract.
class AtXWingKeyPair extends AsymmetricKeyPair {
  AtXWingKeyPair.create(super.publicKey, super.privateKey) : super.create();
}
