import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:pqcrypto/pqcrypto.dart';

/// ML-DSA-65 (FIPS 204) digital signature backed by pure-Dart
/// (`package:pqcrypto`).
///
/// Construct an instance and call [signBytes]/[verifyBytes] (the
/// [AtSignatureAlgorithm] interface) — all key material is passed
/// explicitly. Or use [AtPqc.mlDsa65] (typed [AtSignatureAlgorithm]) for
/// auto-resolved FFI/pure dispatch without touching this class.
final class MlDsa65PureDartAlgo implements AtSignatureAlgorithm {
  MlDsa65PureDartAlgo();

  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.mldsa65;

  /// Null — ML-DSA-65 hashes internally per FIPS 204; there is no separate
  /// choice to declare.
  @override
  HashingAlgoType? get hashingAlgoType => null;

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
    return MlDsa.sign(secretKey, message, DilithiumParams.mlDsa65);
  }

  /// Verify [signature] over [message] against [publicKey] (raw 1952 bytes).
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    return MlDsa.verify(publicKey, message, signature, DilithiumParams.mlDsa65);
  }
}
