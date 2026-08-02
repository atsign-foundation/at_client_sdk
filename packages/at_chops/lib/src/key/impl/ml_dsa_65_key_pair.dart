import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/spec/ml_dsa_65_spec.dart';
import 'package:at_chops/src/key/keys.dart';
import 'package:at_commons/at_commons.dart';

import '../../algorithm/signing/ml_dsa_65_pure_dart.dart';

/// ML-DSA-65 (FIPS 204) signing key pair.
///
/// Both keys are stored as base64-encoded raw bytes:
/// - Public key: 1952 bytes
/// - Secret key: 4032 bytes
class MlDsa65KeyPair extends AsymmetricKeyPair with RawKeyPairBytes {
  /// Throws [AtSigningException] if [publicKey] or [privateKey] does not
  /// base64-decode to the expected ML-DSA-65 length — catching corrupted or
  /// truncated key material as soon as the key pair is built, rather than at
  /// first sign/verify use.
  MlDsa65KeyPair.create(String publicKey, String privateKey)
      : super.create(publicKey, privateKey) {
    final int pubLen = base64Decode(publicKey).length;
    if (pubLen != MlDsa65Sizes.publicKeyBytes) {
      throw AtSigningException(
          'ML-DSA-65 public key must be ${MlDsa65Sizes.publicKeyBytes} bytes '
          '(got $pubLen)');
    }
    final int skLen = base64Decode(privateKey).length;
    if (skLen != MlDsa65Sizes.secretKeyBytes) {
      throw AtSigningException(
          'ML-DSA-65 secret key must be ${MlDsa65Sizes.secretKeyBytes} bytes '
          '(got $skLen)');
    }
  }

  /// Generates an ML-DSA-65 key pair for post-quantum digital signatures.
  ///
  /// Backed by the pure-Dart ML-DSA-65 implementation (via `package:pqcrypto`).
  /// Raw 1952-byte public key and 4032-byte secret key are base64-encoded.
  /// Both keys are serializable and interoperable with the FFI backend.
  static Future<MlDsa65KeyPair> generate() async {
    final (publicKey: Uint8List pub, secretKey: Uint8List sk) =
        await MlDsa65PureDartAlgo().generateKeyPair();
    return MlDsa65KeyPair.create(base64Encode(pub), base64Encode(sk));
  }
}
