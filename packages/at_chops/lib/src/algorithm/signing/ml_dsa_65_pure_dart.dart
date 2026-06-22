import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pqcrypto/pqcrypto.dart';

/// ML-DSA-65 (FIPS 204) digital signature backed by pure-Dart
/// (`package:pqcrypto`).
///
/// **Stateless use** (preferred — all key material passed explicitly):
/// Call the static [generateKeyPair], [signBytes], and [verifyBytes] directly.
///
/// **Stateful use** (implements [AtSigningAlgorithm]):
/// Construct an instance, set [secretKey], then call [sign]. Pass the
/// base64-encoded raw public key as the [publicKey] parameter to [verify].
final class MlDsa65PureDartAlgo implements AtSigningAlgorithm {
  Uint8List? _secretKey;

  MlDsa65PureDartAlgo();

  set secretKey(Uint8List value) => _secretKey = value;

  /// Generate a fresh ML-DSA-65 key pair.
  ///
  /// Returns raw `(publicKey: 1952 bytes, secretKey: 4032 bytes)`.
  static Future<({Uint8List publicKey, Uint8List secretKey})>
      generateKeyPair() async {
    final (Uint8List pk, Uint8List sk) =
        MlDsa.generateKeyPair(DilithiumParams.mlDsa65);
    return (publicKey: pk, secretKey: sk);
  }

  /// Sign [message] with [secretKey] (raw 4032-byte secret key).
  ///
  /// Returns a 3309-byte signature. Signing is hedged per FIPS 204 —
  /// a fresh random value is mixed in, so signatures are non-deterministic.
  static Future<Uint8List> signBytes(
      Uint8List message, Uint8List secretKey) async {
    return MlDsa.sign(secretKey, message, DilithiumParams.mlDsa65);
  }

  /// Verify [signature] over [message] against [publicKey] (raw 1952 bytes).
  static Future<bool> verifyBytes(
      Uint8List message, Uint8List signature, Uint8List publicKey) async {
    return MlDsa.verify(publicKey, message, signature, DilithiumParams.mlDsa65);
  }

  // ── AtSigningAlgorithm ──────────────────────────────────────────────────────

  @override
  Future<Uint8List> sign(Uint8List data) async {
    if (_secretKey == null) {
      throw AtSigningException(
          'ML-DSA-65 secret key must be set before signing');
    }
    return signBytes(data, _secretKey!);
  }

  @override
  Future<bool> verify(Uint8List signedData, Uint8List signature,
      {String? publicKey}) async {
    if (publicKey == null) {
      throw AtSigningException(
          'public key must be provided for ML-DSA-65 signature verification');
    }
    final Uint8List pkBytes = base64Decode(publicKey);
    return verifyBytes(signedData, signature, pkBytes);
  }
}
