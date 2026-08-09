import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Hmac, sha256, sha384;

/// HMAC-SHA256 (RFC 2104). The keyed-hash primitive HKDF is built on; also
/// usable directly for MACs. Wraps `package:crypto` so consumers depend only
/// on at_chops for keyed hashing.
class HmacSha256 {
  /// `HMAC-SHA256(key, data)` → 32 raw bytes.
  static Uint8List compute(Uint8List key, Uint8List data) =>
      Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);
}

/// HKDF-SHA256 (RFC 5869): extract-then-expand key derivation.
///
/// Deterministic — the same `(ikm, salt, info, length)` always yields the
/// same output, so two parties holding the same input key material derive
/// identical sub-keys without communicating (e.g. a shared group secret's
/// per-label `export`, or NoPorts session keys).
class HkdfSha256 {
  /// SHA-256 output size in bytes; the per-block expand step yields this much.
  static const int hashLen = 32;

  /// RFC 5869 **Extract** on its own: `PRK = HMAC-SHA256(salt, ikm)`.
  ///
  /// Separate from [expand] because RFC 9180's key schedule derives several
  /// outputs from a single PRK; re-running extract per output would produce
  /// unrelated keys. [deriveKey] is the fused form for the common case.
  ///
  /// An empty [salt] is HMAC-equivalent to the RFC's "HashLen zeros" default,
  /// since both pad to an all-zero block.
  static Uint8List extract(Uint8List ikm, {Uint8List? salt}) =>
      HmacSha256.compute(salt ?? Uint8List(0), ikm);

  /// RFC 5869 **Expand** on its own:
  /// `T(i) = HMAC-SHA256(prk, T(i-1) || info || i)`, truncated to [length].
  static Uint8List expand(Uint8List prk,
      {Uint8List? info, required int length}) {
    if (length < 1 || length > 255 * hashLen) {
      throw ArgumentError.value(length, 'length',
          'HKDF-SHA256 length must be in 1..${255 * hashLen}');
    }
    final ctx = info ?? Uint8List(0);
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

  /// Derives [length] bytes from input-key-material [ikm], optionally keyed
  /// by [salt] (defaults to all-zeros, per RFC 5869) and bound to a context
  /// [info] (defaults to empty).
  ///
  /// [length] must be in `1..255*32` (the RFC's expand bound). Throws
  /// [ArgumentError] otherwise.
  ///
  /// See [extract] and [expand] for the two halves separately, which RFC 9180's
  /// key schedule needs because it derives several outputs from one PRK.
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

/// HMAC-SHA384 (RFC 2104). The keyed-hash primitive [HkdfSha384] is built on.
class HmacSha384 {
  /// `HMAC-SHA384(key, data)` -> 48 raw bytes.
  static Uint8List compute(Uint8List key, Uint8List data) =>
      Uint8List.fromList(Hmac(sha384, key).convert(data).bytes);
}

/// HKDF-SHA384 (RFC 5869) — the same extract-then-expand construction as
/// [HkdfSha256] at a 48-byte hash.
///
/// Present because it is the KDF in the only published HPKE suite for
/// ML-KEM-1024 (IANA KDF id `0x0002`, alongside KEM `0x0042` and AES-256-GCM),
/// and because CNSA 2.0 specifies SHA-384 alongside ML-KEM-1024. Using
/// HKDF-SHA256 there would mean a suite with no third-party vector.
///
/// RFC 5869 publishes test vectors for SHA-256 and SHA-1 only, so this is
/// attested instead by the HPKE working group's `0x0042` key-schedule vector,
/// which exercises it end to end — see `test/rfc9180_hpke_test.dart`.
class HkdfSha384 {
  /// SHA-384 output size in bytes.
  static const int hashLen = 48;

  /// RFC 5869 Extract: `PRK = HMAC-SHA384(salt, ikm)`.
  static Uint8List extract(Uint8List ikm, {Uint8List? salt}) =>
      HmacSha384.compute(salt ?? Uint8List(0), ikm);

  /// RFC 5869 Expand, truncated to [length].
  static Uint8List expand(Uint8List prk,
      {Uint8List? info, required int length}) {
    if (length < 1 || length > 255 * hashLen) {
      throw ArgumentError.value(length, 'length',
          'HKDF-SHA384 length must be in 1..${255 * hashLen}');
    }
    final ctx = info ?? Uint8List(0);
    final out = <int>[];
    var t = <int>[];
    var counter = 1;
    while (out.length < length) {
      t = HmacSha384.compute(prk, Uint8List.fromList([...t, ...ctx, counter]));
      out.addAll(t);
      counter++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }
}
