import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// A symmetric content key (CK) and its id.
///
/// Application data is AES-256-GCM encrypted under a CK; the CK itself is
/// X-Wing-sealed once to an nskey and written as a discrete conveyance record.
/// Data values cite the CK by [ckKid] and never carry a sealed key inline.
class ContentKey {
  /// Raw 32 bytes of AES-256 key material.
  final Uint8List bytes;

  /// The content key's id — a SHA-256 prefix of the key material, so identical
  /// keys dedupe. Must be unique within `(owner, namespace)`;
  /// [ContentKeyCache.put] refuses a second CK claiming a kid already held.
  ///
  /// The id is public — it rides plaintext `appMetadata` and the conveyance
  /// record's name — so it is only safe while CKs are high-entropy: publishing
  /// 64 bits of a hash turns any guessable CK into an offline check. Mint CKs
  /// from a CSPRNG, never derive them from a label, counter or passphrase.
  final String ckKid;

  ContentKey._(this.bytes, this.ckKid);

  /// Derive the id for [bytes] and pair them.
  factory ContentKey(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError(
          'a content key must be 32 bytes, got ${bytes.length}');
    }
    final digest = sha256.convert(bytes).toString();
    return ContentKey._(bytes, digest.substring(0, 16));
  }

  /// Rebuild from the base64 form conveyed in an `at/nskey` record.
  factory ContentKey.fromBase64(String b64) =>
      ContentKey(Uint8List.fromList(base64Decode(b64)));

  String toBase64() => base64Encode(bytes);
}

/// Cache of decapsulated content keys, keyed by `(owner, namespace, ckKid)`.
///
/// Never key by `ckKid` alone — ids are unique within a namespace, not across
/// them, which is the same `(owner, id)` identity discipline used elsewhere in
/// the SDK. A value in a namespace for which the client holds no nskey private
/// is left undecryptable rather than silently mis-resolved.
class ContentKeyCache {
  final Map<String, ContentKey> _byKid = {};
  final Map<String, String> _currentKidByNamespace = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _key(String owner, String namespace, String ckKid) =>
      '${_scope(owner, namespace)}|$ckKid';

  /// Cache [ck] for `(owner, namespace)` so values citing its `ckKid` resolve.
  ///
  /// This does **not** make it the namespace's current key. Conveyance records
  /// arrive in sync order, which is no order at all, so a CK opened now may be
  /// older than the one already in use — letting an arriving record set the
  /// write key would silently roll new writes back onto a superseded CK.
  /// Only the client that cut the CK calls [putAsCurrent].
  void put(String owner, String namespace, ContentKey ck) {
    final slot = _key(owner, namespace, ck.ckKid);
    final existing = _byKid[slot];
    if (existing != null && !_sameKey(existing.bytes, ck.bytes)) {
      // A kid is a truncated hash, so this is a collision, not a re-delivery.
      // Overwriting would make the displaced CK's data silently undecryptable.
      throw StateError(
          'content key ${ck.ckKid} in $owner:$namespace already holds different '
          'key material — two distinct CKs share one kid');
    }
    _byKid[slot] = ck;
  }

  /// Cache [ck] and make it the key new writes in `(owner, namespace)` encrypt
  /// under. Called by the writer that cut the CK and conveyed it.
  void putAsCurrent(String owner, String namespace, ContentKey ck) {
    put(owner, namespace, ck);
    _currentKidByNamespace[_scope(owner, namespace)] = ck.ckKid;
  }

  static bool _sameKey(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The CK cited by [ckKid], or null on a cache miss.
  ///
  /// A miss is the ordinary out-of-order-sync case: a data value can arrive
  /// before its conveyance record. The caller defers rather than failing hard.
  ContentKey? get(String owner, String namespace, String ckKid) =>
      _byKid[_key(owner, namespace, ckKid)];

  /// The CK new writes in `(owner, namespace)` encrypt under, or null if no CK
  /// has been conveyed for that namespace yet.
  ContentKey? current(String owner, String namespace) {
    final kid = _currentKidByNamespace[_scope(owner, namespace)];
    return kid == null ? null : get(owner, namespace, kid);
  }

  /// Drop a superseded CK. Deleting the conveyance record and evicting here is
  /// the coarse forward-secrecy lever — data written under an evicted CK
  /// becomes undecryptable by design.
  void evict(String owner, String namespace, String ckKid) {
    _byKid.remove(_key(owner, namespace, ckKid));
    final scope = _scope(owner, namespace);
    if (_currentKidByNamespace[scope] == ckKid) {
      _currentKidByNamespace.remove(scope);
    }
  }
}
