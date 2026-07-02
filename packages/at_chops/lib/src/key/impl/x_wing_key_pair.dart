import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/key/keys.dart';

import '../../algorithm/at_pqc.dart';

/// X-Wing hybrid post-quantum/traditional KEM key pair
/// (draft-connolly-cfrg-xwing-kem).
///
/// Public keys are 1216 raw bytes (`pk_ML-KEM-768 || pk_X25519`); the
/// private key is the 32-byte seed from which everything else is re-derived.
/// Both are encoded as base64 strings to fit the existing
/// [AsymmetricKeyPair] String contract.
class XWingKeyPair extends AsymmetricKeyPair {
  XWingKeyPair.create(super.publicKey, super.privateKey) : super.create();

  /// Generates an X-Wing hybrid post-quantum/traditional KEM key pair
  /// (draft-connolly-cfrg-xwing-kem; X25519 + ML-KEM-768).
  ///
  /// Raw 1216-byte public key and 32-byte seed secret key are
  /// base64-encoded. Uses [AtPqc.xWing] — FFI when available, else pure-Dart.
  static Future<XWingKeyPair> generate() async {
    final (publicKey: Uint8List pub, secretKey: Uint8List sk) =
        await AtPqc.xWing.generateKeyPair();
    return XWingKeyPair.create(base64Encode(pub), base64Encode(sk));
  }

  Uint8List get publicKeyBytes => base64Decode(atPublicKey.publicKey);
  Uint8List get privateKeyBytes => base64Decode(atPrivateKey.privateKey);
}
