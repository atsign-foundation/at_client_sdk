import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';

/// HMAC-SHA256 (RFC 2104). The keyed-hash primitive HKDF is built on; also
/// usable directly for MACs. Wraps pointycastle so consumers depend only on
/// at_chops for keyed hashing.
class HmacSha256 {
  /// `HMAC-SHA256(key, data)` → 32 raw bytes.
  static Uint8List compute(Uint8List key, Uint8List data) =>
      (HMac.withDigest(SHA256Digest())..init(KeyParameter(key))).process(data);
}

/// HKDF-SHA256 (RFC 5869): extract-then-expand key derivation.
///
/// Deterministic — the same `(ikm, salt, info, length)` always yields the
/// same output, so two parties holding the same input key material derive
/// identical sub-keys without communicating (e.g. a [SecureGroup]'s
/// per-label `export`, or NoPorts session keys).
class HkdfSha256 {
  /// SHA-256 output size in bytes; the per-block expand step yields this much.
  static const int hashLen = 32;

  /// Derives [length] bytes from input-key-material [ikm], optionally keyed
  /// by [salt] (defaults to all-zeros, per RFC 5869) and bound to a context
  /// [info] (defaults to empty).
  ///
  /// [length] must be in `1..255*32` (the RFC's expand bound). Throws
  /// [ArgumentError] otherwise.
  static Uint8List deriveKey(
    Uint8List ikm, {
    Uint8List? salt,
    Uint8List? info,
    required int length,
  }) {
    if (length < 1 || length > 255 * hashLen) {
      throw ArgumentError.value(length, 'length',
          'HKDF-SHA256 length must be in 1..${255 * hashLen}');
    }
    final ctx = info ?? Uint8List(0);
    // Extract: PRK = HMAC(salt, IKM). An empty salt key is HMAC-equivalent to
    // the RFC's "HashLen zeros" default (both pad to an all-zero block).
    final prk = HmacSha256.compute(salt ?? Uint8List(0), ikm);
    // Expand: T(i) = HMAC(PRK, T(i-1) | info | i), OKM = T(1) | T(2) | ...
    final out = <int>[];
    var t = <int>[];
    var counter = 1;
    while (out.length < length) {
      t = HmacSha256.compute(prk, Uint8List.fromList([...t, ...ctx, counter]));
      out.addAll(t);
      counter++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }
}
