import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/key/keys.dart';

import '../../algorithm/encryption/x25519_pure_dart_algo.dart';

/// X25519 key pair used for Diffie–Hellman key agreement.
///
/// Both public and private keys are 32-byte raw values encoded as base64
/// strings, so they fit the existing [AsymmetricKeyPair] String contract.
/// Callers consuming the bytes should `base64Decode` at the algorithm
/// boundary.
class X25519KeyPair extends AsymmetricKeyPair {
  X25519KeyPair.create(super.publicKey, super.privateKey) : super.create();

  /// Generates an X25519 key pair for Diffie–Hellman key agreement.
  ///
  /// Backed by the pure-Dart X25519 implementation (via `package:cryptography`).
  /// Raw 32-byte public and private keys are base64-encoded so they fit the
  /// existing String-typed key contract.
  static Future<X25519KeyPair> generate() async {
    final (publicKey: Uint8List pub, privateKey: Uint8List priv) =
        await X25519PureDartAlgo.instance.generateKeyPair();
    return X25519KeyPair.create(base64Encode(pub), base64Encode(priv));
  }
}
