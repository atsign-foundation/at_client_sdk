import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// The RFC 5869 extract-then-expand construction, parameterised by hash.
///
/// Package-internal: the exported surface is the hash-pinned facades in
/// `hkdf.dart` ([HkdfSha256] is published API), whose names carry the hash the
/// way the RFC's own vectors do. This class exists so the expand loop, its
/// length guard and the HMAC wrapper have one implementation instead of one
/// copy per hash.
final class Hkdf {
  static final Hkdf sha256 = Hkdf._(crypto.sha256, 32, 'HKDF-SHA256');
  static final Hkdf sha384 = Hkdf._(crypto.sha384, 48, 'HKDF-SHA384');

  final crypto.Hash _hash;

  /// The hash's output size in bytes; the per-block expand step yields this
  /// much.
  final int hashLen;

  /// How a diagnostic names this construction, e.g. `HKDF-SHA256`.
  final String _name;

  Hkdf._(this._hash, this.hashLen, this._name);

  /// `HMAC-hash(key, data)` (RFC 2104), [hashLen] raw bytes.
  Uint8List hmac(Uint8List key, Uint8List data) =>
      Uint8List.fromList(crypto.Hmac(_hash, key).convert(data).bytes);

  /// RFC 5869 **Extract**: `PRK = HMAC-hash(salt, ikm)`.
  ///
  /// An empty [salt] is HMAC-equivalent to the RFC's "HashLen zeros" default,
  /// since both pad to an all-zero block.
  Uint8List extract(Uint8List ikm, {Uint8List? salt}) =>
      hmac(salt ?? Uint8List(0), ikm);

  /// RFC 5869 **Expand**:
  /// `T(i) = HMAC-hash(prk, T(i-1) || info || i)`, truncated to [length].
  Uint8List expand(Uint8List prk, {Uint8List? info, required int length}) {
    if (length < 1 || length > 255 * hashLen) {
      throw ArgumentError.value(
          length, 'length', '$_name length must be in 1..${255 * hashLen}');
    }
    final ctx = info ?? Uint8List(0);
    final out = <int>[];
    var t = <int>[];
    var counter = 1;
    while (out.length < length) {
      t = hmac(prk, Uint8List.fromList([...t, ...ctx, counter]));
      out.addAll(t);
      counter++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  /// The fused form: [expand] over [extract]'s PRK.
  Uint8List deriveKey(Uint8List ikm,
          {Uint8List? salt, Uint8List? info, required int length}) =>
      expand(extract(ikm, salt: salt), info: info, length: length);
}
