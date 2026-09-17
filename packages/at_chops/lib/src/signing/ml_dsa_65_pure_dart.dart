import 'dart:async';
import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/spec/ml_dsa_65_spec.dart';
import 'package:at_chops/src/spec/output_length.dart';
import 'package:at_commons/at_commons.dart';
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
  String get name => SigningAlgoType.mldsa65.name;

  /// Generate a fresh ML-DSA-65 key pair.
  ///
  /// Returns raw `(publicKey: 1952 bytes, secretKey: 4032 bytes)`.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final (Uint8List pk, Uint8List sk) =
        MlDsa.generateKeyPair(DilithiumParams.mlDsa65);
    checkOutputLength(pk.length, MlDsa65Sizes.publicKeyBytes,
        operation: 'ML-DSA-65 generateKeyPair', label: 'public key');
    checkOutputLength(sk.length, MlDsa65Sizes.secretKeyBytes,
        operation: 'ML-DSA-65 generateKeyPair', label: 'secret key');
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
    return signBytesSync(message, secretKey: secretKey);
  }

  /// Verify [signature] over [message] against [publicKey] (raw 1952 bytes).
  ///
  /// Throws [AtSigningVerificationException] if the signature does not verify.
  @override
  Future<void> verifyBytes(Uint8List message,
          {required Uint8List signature, required Uint8List publicKey}) async =>
      verifyBytesSync(message, signature: signature, publicKey: publicKey);

  /// Synchronous [signBytes]. The pure-Dart computation is synchronous —
  /// this exposes it to callers that cannot await, such as envelope signing.
  ///
  /// The length checks live here rather than in [signBytes] because the
  /// synchronous callers reach this method directly; validating in the async
  /// wrapper would leave exactly the callers that bypass it unguarded.
  static Uint8List signBytesSync(Uint8List message,
      {required Uint8List secretKey}) {
    MlDsa65Sizes.validateSecretKey(secretKey);
    final Uint8List sig =
        MlDsa.sign(secretKey, message, DilithiumParams.mlDsa65);
    checkOutputLength(sig.length, MlDsa65Sizes.signatureBytes,
        operation: 'ML-DSA-65 sign', label: 'signature');
    return sig;
  }

  /// Synchronous [verifyBytes], and it throws for the same reason: a
  /// verification that did not happen and one that failed are the same answer
  /// to the caller, and only an exception makes the difference impossible to
  /// drop. A wrong-length key or signature never verifies, so it takes the
  /// same exit as a mismatch.
  static void verifyBytesSync(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) {
    if (!MlDsa65Sizes.hasValidVerifyLengths(publicKey, signature) ||
        !MlDsa.verify(publicKey, message, signature, DilithiumParams.mlDsa65)) {
      throw AtSigningVerificationException(
          '${SigningAlgoType.mldsa65.name} signature verification failed');
    }
  }
}
