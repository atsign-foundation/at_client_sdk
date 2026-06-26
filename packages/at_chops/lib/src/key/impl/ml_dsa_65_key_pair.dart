import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/key/keys.dart';

import '../../algorithm/signing/ml_dsa_65_pure_dart.dart';

/// ML-DSA-65 (FIPS 204) signing key pair.
///
/// Both keys are stored as base64-encoded raw bytes:
/// - Public key: 1952 bytes
/// - Secret key: 4032 bytes
class MlDsa65KeyPair extends AsymmetricKeyPair {
  MlDsa65KeyPair.create(super.publicKey, super.privateKey) : super.create();

  /// Generates an ML-DSA-65 key pair for post-quantum digital signatures.
  ///
  /// Backed by the pure-Dart ML-DSA-65 implementation (via `package:pqcrypto`).
  /// Raw 1952-byte public key and 4032-byte secret key are base64-encoded.
  /// Both keys are serializable and interoperable with the FFI backend.
  static Future<MlDsa65KeyPair> generate() async {
    final (publicKey: Uint8List pub, secretKey: Uint8List sk) =
        await MlDsa65PureDartAlgo.generateKeyPair();
    return MlDsa65KeyPair.create(base64Encode(pub), base64Encode(sk));
  }

  Uint8List get publicKeyBytes => base64Decode(atPublicKey.publicKey);
  Uint8List get privateKeyBytes => base64Decode(atPrivateKey.privateKey);
}
