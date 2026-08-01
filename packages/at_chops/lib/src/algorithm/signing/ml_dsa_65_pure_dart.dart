import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/signing/ml_dsa_65_validation.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pqcrypto/pqcrypto.dart';

/// ML-DSA-65 (FIPS 204) digital signature backed by pure-Dart
/// (`package:pqcrypto`).
///
/// Construct an instance and call [signBytes]/[verifyBytes] (the
/// [AtSignatureAlgorithm] interface) — all key material is passed
/// explicitly. Or use [AtPqc.mlDsa65] (typed [AtSignatureAlgorithm]) for
/// auto-resolved FFI/pure dispatch without touching this class.
///
/// The stateful [AtSigningAlgorithm] path ([secretKey]/[sign]/[verify]) is
/// retained for compatibility with the published 3.3.0 surface and for
/// `AtChopsImpl`'s signing/verification dispatch; it is deprecated — new
/// code should pass key material per call.
final class MlDsa65PureDartAlgo
    implements AtSigningAlgorithm, AtSignatureAlgorithm {
  Uint8List? _secretKey;

  MlDsa65PureDartAlgo();

  @Deprecated('Pass the secret key to signBytes instead.')
  set secretKey(Uint8List value) => _secretKey = value;

  /// Generate a fresh ML-DSA-65 key pair.
  ///
  /// Returns raw `(publicKey: 1952 bytes, secretKey: 4032 bytes)`.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final (Uint8List pk, Uint8List sk) =
        MlDsa.generateKeyPair(DilithiumParams.mlDsa65);
    return (publicKey: pk, secretKey: sk);
  }

  // ── AtSignatureAlgorithm ────────────────────────────────────────────────

  /// Sign [message] with [secretKey] (raw 4032-byte secret key).
  ///
  /// Returns a 3309-byte signature. Signing is hedged per FIPS 204 —
  /// a fresh random value is mixed in, so signatures are non-deterministic.
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    validateSecretKey(secretKey);
    return MlDsa.sign(secretKey, message, DilithiumParams.mlDsa65);
  }

  /// Verify [signature] over [message] against [publicKey] (raw 1952 bytes).
  ///
  /// Never throws — returns `false` for malformed or attacker-controlled
  /// input, matching [MlDsa.verify]'s own contract.
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    if (!hasValidVerifyLengths(publicKey, signature)) return false;
    return MlDsa.verify(publicKey, message, signature, DilithiumParams.mlDsa65);
  }

  // ── AtSigningAlgorithm (deprecated stateful path) ───────────────────────

  @Deprecated('Use signBytes with explicit key material instead.')
  @override
  Future<Uint8List> sign(Uint8List data) async {
    if (_secretKey == null) {
      throw AtSigningException(
          'ML-DSA-65 secret key must be set before signing');
    }
    return signBytes(data, secretKey: _secretKey!);
  }

  @Deprecated('Use verifyBytes with explicit key material instead.')
  @override
  Future<bool> verify(Uint8List signedData, Uint8List signature,
      {String? publicKey}) async {
    if (publicKey == null) {
      throw AtSigningException(
          'public key must be provided for ML-DSA-65 signature verification');
    }
    final Uint8List pkBytes = base64Decode(publicKey);
    return verifyBytes(signedData, signature: signature, publicKey: pkBytes);
  }
}
