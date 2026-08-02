import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';

/// Throws [StateError] unless [actual] equals [expected].
///
/// Shared by every PQ backend (ML-KEM-768, ML-DSA-65, X-Wing — FFI and
/// pure-Dart) to check a backend's own output against its FIPS 203/204/
/// X-Wing-draft fixed size. A mismatch here is a backend bug (wrong OpenSSL
/// version, algorithm mix-up), not caller input, so it must throw
/// unconditionally rather than via `assert()` — asserts strip in release
/// builds, letting a wrong-size output propagate into buffers sized for the
/// expected length.
void checkOutputLength(int actual, int expected,
    {required String operation, required String label}) {
  if (actual != expected) {
    throw StateError(
        '$operation produced a $actual-byte $label, expected $expected');
  }
}

/// [AtSignatureAlgorithm.name] for ML-DSA-65 — one literal shared by
/// [MlDsa65FfiAlgo] and [MlDsa65PureDartAlgo] so a downstream protocol sees
/// the same identifier regardless of which backend is in play.
const String mlDsa65AlgorithmName = 'ml-dsa-65';

/// FIPS 204 ML-DSA-65 fixed byte sizes — the single source of truth shared by
/// [MlDsa65FfiAlgo], [MlDsa65PureDartAlgo], and [MlDsa65KeyPair] so all three
/// enforce identical lengths regardless of which backend is in play.
abstract final class MlDsa65Sizes {
  /// Raw public key size.
  static const int publicKeyBytes = 1952;

  /// Raw secret key size.
  static const int secretKeyBytes = 4032;

  /// Signature size.
  static const int signatureBytes = 3309;
}

/// Throws [AtSigningException] unless [secretKey] is exactly
/// [MlDsa65Sizes.secretKeyBytes] long.
///
/// `secretKey` is caller-supplied, trusted local input (unlike a signature
/// being verified), so a length mismatch is a caller bug worth throwing for —
/// silently truncating an over-long key and signing with the wrong material
/// is far worse than failing loudly.
void validateSecretKey(Uint8List secretKey) {
  if (secretKey.length != MlDsa65Sizes.secretKeyBytes) {
    throw AtSigningException(
        'ML-DSA-65 secret key must be ${MlDsa65Sizes.secretKeyBytes} bytes '
        '(got ${secretKey.length})');
  }
}

/// True iff [publicKey] and [signature] have the lengths FIPS 204 ML-DSA-65
/// requires.
///
/// Both are wire-supplied, attacker-controlled input during verification —
/// callers must return `false` immediately when this is `false`, never
/// throw. Malformed/attacker-controlled verify input is expected traffic,
/// not a caller bug.
bool hasValidVerifyLengths(Uint8List publicKey, Uint8List signature) {
  return publicKey.length == MlDsa65Sizes.publicKeyBytes &&
      signature.length == MlDsa65Sizes.signatureBytes;
}
