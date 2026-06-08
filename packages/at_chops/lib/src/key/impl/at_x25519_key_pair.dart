import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/key/at_key_pair.dart';

/// X25519 key pair used for Diffie–Hellman key agreement.
///
/// Both public and private keys are 32-byte raw values encoded as base64
/// strings, so they fit the existing [AsymmetricKeyPair] String contract.
/// Callers consuming the bytes should `base64Decode` at the algorithm
/// boundary.
class AtX25519KeyPair extends AsymmetricKeyPair {
  AtX25519KeyPair.create(super.publicKey, super.privateKey) : super.create();

  /// Construct from raw 32-byte [publicKey] and [privateKey] bytes,
  /// base64-encoding them to fit the [AsymmetricKeyPair] String contract.
  AtX25519KeyPair.fromBytes(Uint8List publicKey, Uint8List privateKey)
      : super.create(base64Encode(publicKey), base64Encode(privateKey));
}
