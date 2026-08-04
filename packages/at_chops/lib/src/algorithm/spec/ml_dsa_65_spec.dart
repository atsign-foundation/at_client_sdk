import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';

/// FIPS 204 ML-DSA-65 fixed byte sizes and input validators — the single
/// source of truth shared by `MlDsa65FfiAlgo`, `MlDsa65PureDartAlgo`, and
/// `MlDsa65KeyPair` so all three enforce identical lengths regardless of
/// which backend is in play.
abstract final class MlDsa65Sizes {
  /// Raw public key size.
  static const int publicKeyBytes = 1952;

  /// Raw secret key size.
  static const int secretKeyBytes = 4032;

  /// Signature size.
  static const int signatureBytes = 3309;

  /// Throws [AtSigningException] unless [secretKey] is exactly
  /// [secretKeyBytes] long.
  ///
  /// `secretKey` is caller-supplied, trusted local input (unlike a signature
  /// being verified), so a length mismatch is a caller bug worth throwing
  /// for — silently truncating an over-long key and signing with the wrong
  /// material is far worse than failing loudly.
  static void validateSecretKey(Uint8List secretKey) {
    if (secretKey.length != secretKeyBytes) {
      throw AtSigningException(
          'ML-DSA-65 secret key must be $secretKeyBytes bytes '
          '(got ${secretKey.length})');
    }
  }

  /// True iff [publicKey] and [signature] have the lengths FIPS 204
  /// ML-DSA-65 requires.
  ///
  /// Both are wire-supplied, attacker-controlled input during verification —
  /// callers must return `false` immediately when this is `false`, never
  /// throw. Malformed/attacker-controlled verify input is expected traffic,
  /// not a caller bug.
  static bool hasValidVerifyLengths(Uint8List publicKey, Uint8List signature) {
    return publicKey.length == publicKeyBytes &&
        signature.length == signatureBytes;
  }
}
