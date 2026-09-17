import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// A symmetric content key (CK) and its id.
///
/// Application data is AES-256-GCM encrypted under a CK; the CK is KEM-sealed
/// once to an nskey and written as a discrete conveyance record, which values
/// cite by [ckKid] rather than carrying a sealed key inline.
class ContentKey {
  /// Raw 32 bytes of AES-256 key material.
  final Uint8List bytes;

  /// The content key's id — a SHA-256 prefix of the key material, so identical
  /// keys dedupe. Must be unique within `(owner, namespace)`.
  ///
  /// The id is public, riding plaintext `appMetadata` and the conveyance
  /// record's name, so it is only safe while CKs are high-entropy: mint them
  /// from a CSPRNG, never from a label, counter or passphrase.
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

  /// The base64 form written into an `at/nskey` conveyance record.
  String toBase64() => base64Encode(bytes);
}

/// Cache of decapsulated content keys, keyed by `(owner, namespace, ckKid)`.
///
/// Never key by `ckKid` alone: ids are unique within a namespace, not across
/// them, so a value whose namespace this client cannot open must stay
/// undecryptable rather than resolve to another namespace's key.
class ContentKeyCache {
  final Map<String, ContentKey> _byKid = {};
  final Map<String, String> _currentKidByNamespace = {};
  final Map<String, String> _currentNskeyKidByNamespace = {};
  final Map<String, DateTime> _currentCutAtByNamespace = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _key(String owner, String namespace, String ckKid) =>
      '${_scope(owner, namespace)}|$ckKid';

  /// Cache [ck] for `(owner, namespace)` so values citing its `ckKid` resolve.
  ///
  /// Does not make it the namespace's current key: conveyance records arrive
  /// in sync order, so a CK opened now may be older than the one already in
  /// use. Only the client that cut a CK calls [putAsCurrent].
  void put(String owner, String namespace, ContentKey ck) {
    final slot = _key(owner, namespace, ck.ckKid);
    final existing = _byKid[slot];
    if (existing != null && !_sameKey(existing.bytes, ck.bytes)) {
      // NOTE: a kid is a truncated hash, so this is a collision, not a
      // re-delivery — overwriting would silently orphan the displaced CK's
      // data.
      throw StateError(
          'content key ${ck.ckKid} in $owner:$namespace already holds different '
          'key material — two distinct CKs share one kid');
    }
    _byKid[slot] = ck;
  }

  /// Cache [ck] and make it the key new writes in `(owner, namespace)` encrypt
  /// under, recording the nskey generation it was conveyed to.
  ///
  /// [nskeyKid] is what lets a sender notice a rotation: once the recipient's
  /// advertised generation no longer matches, the current CK is stale.
  /// [cutAt] is when the CK came into being, which a rotation policy judges it
  /// against: the caller that cut it passes nothing and gets this device's
  /// clock, while one that read it back passes the conveyance record's
  /// `createdAt`, the only date two devices can agree on.
  void putAsCurrent(
      String owner, String namespace, ContentKey ck, String nskeyKid,
      {DateTime? cutAt}) {
    put(owner, namespace, ck);
    final scope = _scope(owner, namespace);
    _currentKidByNamespace[scope] = ck.ckKid;
    _currentNskeyKidByNamespace[scope] = nskeyKid;
    _currentCutAtByNamespace[scope] = cutAt ?? DateTime.now().toUtc();
  }

  /// When the current CK for `(owner, namespace)` was cut, or null if there is
  /// no current CK.
  DateTime? currentCutAt(String owner, String namespace) =>
      _currentCutAtByNamespace[_scope(owner, namespace)];

  /// The nskey generation the current CK was conveyed to, or null if there is
  /// no current CK for `(owner, namespace)`.
  String? currentNskeyKid(String owner, String namespace) =>
      _currentNskeyKidByNamespace[_scope(owner, namespace)];

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
  /// before its conveyance record, so callers defer rather than fail hard.
  ContentKey? get(String owner, String namespace, String ckKid) =>
      _byKid[_key(owner, namespace, ckKid)];

  /// The CK new writes in `(owner, namespace)` encrypt under, or null if no CK
  /// has been conveyed for that namespace yet.
  ContentKey? current(String owner, String namespace) {
    final kid = _currentKidByNamespace[_scope(owner, namespace)];
    return kid == null ? null : get(owner, namespace, kid);
  }

  /// Drop a superseded CK, after which data written under it can no longer be
  /// read here.
  void evict(String owner, String namespace, String ckKid) {
    _byKid.remove(_key(owner, namespace, ckKid));
    final scope = _scope(owner, namespace);
    if (_currentKidByNamespace[scope] == ckKid) {
      _currentKidByNamespace.remove(scope);
      _currentNskeyKidByNamespace.remove(scope);
      _currentCutAtByNamespace.remove(scope);
    }
  }
}
