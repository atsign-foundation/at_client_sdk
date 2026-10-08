import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show ckConveyanceKey, ckSiblingCopyKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/util/swallowed_error.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show visibleForTesting;

final _logger = AtSignLogger('SymmetricAesGcmProvider');

/// The value cites a CK this client cannot resolve *yet*.
///
/// Retry the read once the conveyance record — for a shared value, the
/// recipient's cached copy of it — syncs, where a plain [AtDecryptionException]
/// means give up; a CK deleted for forward secrecy surfaces here too and never
/// resolves.
class ContentKeyUnavailableException extends AtDecryptionException {
  /// The kid the value cited, as it appears in `appMetadata`.
  final String ckKid;

  ContentKeyUnavailableException(this.ckKid, String message) : super(message);
}

/// Layer 3 of the nskey data path: application data, AES-256-GCM under a
/// content key.
///
/// A value carries its ciphertext and *cites* a CK by `ckKid` rather than
/// carrying a sealed key inline; the CK is resolved from the [ContentKeyCache],
/// which the `at/nskey` provider populates when the matching conveyance record
/// — for a shared value, the recipient's cached copy of it — syncs.
class SymmetricAesGcmProvider
    implements
        CryptoProvider,
        PreparesWrites,
        HandlesSelectively,
        ReportsReadiness {
  final ContentKeyCache cache;

  /// Mints and conveys a content key when a destination has none, or when the
  /// one in hand was sealed to a generation the destination has rotated away
  /// from. Null leaves the caller responsible for conveying a CK first.
  final CkManager? ckManager;

  SymmetricAesGcmProvider({required this.cache, this.ckManager});

  /// Serves a namespaced key that is not `local:`.
  ///
  /// The nskey data path is scoped to `(owner, namespace)` throughout, and a
  /// `local:` key never syncs — encrypting it under a content key that is
  /// itself conveyed by a synced record would make device-local state depend on
  /// a mechanism built for data that leaves the device.
  @override
  bool canHandle(AtKey atKey) =>
      !atKey.isLocal && atKey.namespace != null && atKey.namespace!.isNotEmpty;

  @override
  String get id => symmetricAesGcmCryptoProviderId;

  /// Runs before the write pipeline starts, which is the only place a CK can be
  /// conveyed — see [PreparesWrites].
  @override
  Future<void> prepareForWrite(CryptoContext context, AtKey atKey,
          {bool? useRemoteAtServer}) async =>
      await ckManager?.ensureCurrent(context, atKey,
          useRemoteAtServer: useRemoteAtServer);

  /// Answers the question a write would otherwise answer by failing: has
  /// [atSign] published an nskey for [namespace]?
  ///
  /// The lookup is the same one a write makes and shares its cache, so asking
  /// before writing costs nothing extra, and a "no" is one this client has just
  /// confirmed rather than a remembered miss.
  ///
  /// Without a [ckManager] this provider does not resolve keys at all; the
  /// caller conveys content keys itself and is the one that knows.
  @override
  Future<bool> isReadyFor(
          CryptoContext context, String atSign, String namespace) async =>
      ckManager == null ||
      await ckManager!.resolver.resolve(atSign, namespace) != null;

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String plaintext) async {
    final owner = _nskeyOwnerOf(atKey);
    final namespace = _namespaceOf(atKey);
    final ckNs = await _ckNamespaceOf(owner, namespace);

    final ck = cache.current(owner, ckNs);
    if (ck == null) {
      throw AtEncryptionException(
          'no content key established for $owner:$ckNs — convey a CK via '
          'an $nskeyCryptoProviderId record before writing data');
    }

    final salt = _freshSalt();
    final iv = InitialisationVector.random(AesGcm256EncryptionAlgo.nonceLength);
    final ciphertext = await AesGcm256EncryptionAlgo(valueKeyOf(ck, salt))
        .encrypt(_toBytes(atKey, plaintext), iv: iv, aad: _aad(atKey));

    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'ckKid': ck.ckKid,
        'salt': base64Encode(salt),
        'iv': base64Encode(iv.ivBytes),
        // NOTE: AtKey.fromString splits at the last dot, so a multi-segment
        // namespace cannot be recovered from the wire string.
        'ns': namespace,
        // NOTE: without this a reader would hunt for the conveyance at the
        // wrong level whenever resolution walked up, and report "not yet
        // synced" for an intact record.
        'ckNs': ckNs,
      },
    );

    return base64Encode(ciphertext);
  }

  /// Plaintext reaches a provider as an opaque String: `Base2e15` for a binary
  /// record, ordinary text otherwise. Round-tripping binary through UTF-8 is
  /// lossless (Base2e15 emits only U+3400–U+D7A3, clear of the surrogates) but
  /// costs 3 bytes per 15 bits, so honour `isBinary` and carry the real bytes.
  static Uint8List _toBytes(AtKey atKey, String plaintext) =>
      atKey.metadata.isBinary == true
          ? Base2e15.decode(plaintext)
          : Uint8List.fromList(utf8.encode(plaintext));

  static String _fromBytes(AtKey atKey, Uint8List bytes) =>
      atKey.metadata.isBinary == true
          ? Base2e15.encode(bytes)
          : utf8.decode(bytes);

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    final owner = _nskeyOwnerOf(atKey);
    final additional = atKey.metadata.appMetadata?.additional ?? const {};

    final namespace = additional['ckNs'] as String? ?? _namespaceOf(atKey);

    final ckKid = additional['ckKid'];
    final ivB64 = additional['iv'];
    if (ckKid is! String || ivB64 is! String) {
      throw AtDecryptionException(
          'an $symmetricAesGcmCryptoProviderId value must carry ckKid and iv '
          'in appMetadata');
    }

    final ck = cache.get(owner, namespace, ckKid) ??
        await _resolveFromConveyance(context, atKey, owner, namespace, ckKid);
    if (ck == null) {
      throw ContentKeyUnavailableException(
          ckKid,
          'content key $ckKid not yet available for $owner:$namespace — its '
          'conveyance record has not synced, or the key was rotated away');
    }

    final saltB64 = additional['salt'];
    if (saltB64 != null && saltB64 is! String) {
      throw AtDecryptionException(
          'an $symmetricAesGcmCryptoProviderId value carries a salt that is not '
          'a string');
    }
    final AESKey key;
    if (saltB64 == null) {
      // NOTE: a value written before per-value keys existed is encrypted under
      // the content key itself.
      key = AESKey(ck.toBase64());
    } else {
      final List<int> salt;
      try {
        salt = base64Decode(saltB64 as String);
      } on FormatException catch (e) {
        throw AtDecryptionException(
            'an $symmetricAesGcmCryptoProviderId value carries a salt that is '
            'not base64: ${e.message}');
      }
      if (salt.length != saltLength) {
        throw AtDecryptionException(
            'an $symmetricAesGcmCryptoProviderId value carries a '
            '${salt.length}-byte salt, and the salt is $saltLength bytes');
      }
      key = valueKeyOf(ck, salt);
    }
    final plain = await AesGcm256EncryptionAlgo(key).decrypt(
      Uint8List.fromList(base64Decode(ciphertext)),
      iv: InitialisationVector(Uint8List.fromList(base64Decode(ivB64))),
      aad: _aad(atKey),
    );
    return _fromBytes(atKey, plain);
  }

  /// How many bytes of fresh randomness each value's key is derived with.
  static const int saltLength = 32;

  static final Random _random = Random.secure();

  static Uint8List _freshSalt() => Uint8List.fromList(
      List<int>.generate(saltLength, (_) => _random.nextInt(256)));

  /// The HKDF `info` a value key is derived under.
  static final Uint8List _valueKeyInfo =
      Uint8List.fromList(utf8.encode('at/symmetric/AES/GCM/value-key/v1'));

  /// The AES key one value is encrypted under: HKDF-SHA256 over [ck], salted
  /// with that value's own [salt].
  ///
  /// A fresh key per value means no `(key, nonce)` pair repeats however many
  /// values share a content key and however long it stays current, so the
  /// random-nonce limit on AES-GCM does not bound a content key's use.
  @visibleForTesting
  static AESKey valueKeyOf(ContentKey ck, List<int> salt) =>
      AESKey(base64Encode(HkdfSha256.deriveKey(ck.bytes,
          salt: Uint8List.fromList(salt), info: _valueKeyInfo, length: 32)));

  /// Binds a value's ciphertext to the record it was written under.
  ///
  /// A content key covers every record in an `(nskey owner, namespace)` scope,
  /// so without this anyone who can write the store can move a valid ciphertext
  /// between records in that scope and it still authenticates, AEAD tag intact.
  /// Writer and reader must derive byte-identical AAD, so it is composed from
  /// the AtKey's fields rather than `toString()`, with the name and namespace
  /// rejoined: `AtKey.fromString` cuts at the last dot, so the two sides
  /// disagree on where they split but agree on the joined name.
  static List<int> _aad(AtKey atKey) => utf8.encode([
        symmetricAesGcmCryptoProviderId,
        atKey.sharedBy ?? '',
        atKey.sharedWith ?? '',
        fullNameOf(atKey),
      ].join(':'));

  /// `<key>.<namespace>` — the record's address below the owner, independent of
  /// where the two were split.
  @visibleForTesting
  static String fullNameOf(AtKey atKey) {
    final ns = atKey.namespace;
    return (ns == null || ns.isEmpty) ? atKey.key : '${atKey.key}.$ns';
  }

  /// Where the content key for `(owner, namespace)` lives.
  ///
  /// Without a [ckManager] this provider does no resolution — the caller
  /// conveys content keys itself and addresses them at the value's own
  /// namespace.
  Future<String> _ckNamespaceOf(String owner, String namespace) async =>
      (await ckManager?.resolver.resolve(owner, namespace))?.namespace ??
      namespace;

  /// Second chance on a cache miss: read the conveyance record so the
  /// `at/nskey` provider decapsulates and caches it as a side effect, then
  /// look the CK up again rather than taking it from the read.
  ///
  /// **For a value this atSign shared, its sibling copy**, the only record of
  /// that key sealed to this atSign; the recipient's conveyance is never read.
  ///
  /// **For a shared value, the recipient's cached copy first**, which its
  /// atServer made from the conveyance's notification: a restarted recipient
  /// opens what was shared with it while the sender's atServer is unreachable.
  /// The conveyance itself is read after it, since one written before shares
  /// carried a `ttr` has no cached copy.
  ///
  /// **Each from local storage first, then the atServer.** The remote leg is not an
  /// optimisation: a value delivered remote-only — which every notification is
  /// — cites a conveyance its sender wrote remote-first, so the record is on
  /// the atServer before the value arrives and may not reach local storage
  /// until sync gets round to it. `NotificationServiceImpl` **drops** a
  /// notification it cannot transform and never re-delivers it, so a
  /// local-only read here is not a slow path, it is a lost value.
  ///
  /// A record that is nowhere is not an error and yields null. A record that
  /// *is* there and will not open is re-thrown from either leg — a failed AEAD,
  /// a malformed envelope or a kid collision means tampering or corruption, and
  /// reporting it as "not yet synced" would hide it behind advice to keep
  /// polling.
  Future<ContentKey?> _resolveFromConveyance(
    CryptoContext context,
    AtKey value,
    String owner,
    String namespace,
    String ckKid,
  ) async {
    final conveyance = openableConveyanceKeyFor(
        value, ckKid, namespace, context.atClient.getCurrentAtSign());

    /// Returns true when the record was read and opened. A read that finds
    /// nothing returns false; a record that will not open still throws.
    Future<bool> read(AtKey conveyance, {required bool remote}) async {
      try {
        await context.atClient.get(conveyance,
            getRequestOptions: remote
                ? (GetRequestOptions()..useRemoteAtServer = true)
                : null);
        return true;
      } on AtDecryptionException {
        rethrow;
      } on StateError {
        // ContentKeyCache.put refuses two distinct CKs claiming one kid.
        rethrow;
      } on CryptoProviderNotRegistered {
        // NOTE: the record is there and will not open — reporting it as absent
        // would send the caller to wait for a sync that has already happened.
        rethrow;
      } on AtKeyNotFoundException {
        return false;
      } on KeyNotFoundException {
        return false;
      } catch (e) {
        if (e is StoppedException) rethrow;
        // NOTE: an unexpected failure lands here as well and is reported to
        // the caller as "no such record", so the log is its only trace.
        logSwallowed(
            _logger,
            e,
            'Could not read the conveyance $conveyance '
            '(remote: $remote), so its content key stays unresolved: $e');
        return false;
      }
    }

    final sharedWith = conveyance.sharedWith;
    if (sharedWith != null &&
        conveyance.sharedBy != context.atClient.getCurrentAtSign()) {
      final cachedCopy = AtKey()
        ..key = conveyance.key
        ..namespace = conveyance.namespace
        ..sharedBy = conveyance.sharedBy
        ..sharedWith = sharedWith
        ..metadata = (Metadata()..isCached = true);
      for (final remote in const [false, true]) {
        if (await read(cachedCopy, remote: remote)) {
          final hit = cache.get(owner, namespace, ckKid);
          if (hit != null) return hit;
        }
      }
    }

    if (await read(conveyance, remote: false)) {
      final local = cache.get(owner, namespace, ckKid);
      if (local != null) return local;
    }
    if (await read(conveyance, remote: true)) {
      return cache.get(owner, namespace, ckKid);
    }
    return null;
  }

  /// The at-key the CK for [value] was conveyed under — see [ckConveyanceKey],
  /// which owns the format.
  static AtKey conveyanceKeyFor(AtKey value, String ckKid, String ckNs) =>
      ckConveyanceKey(value, ckKid, ckNs);

  /// The record [me] opens the CK for [value] from: the sibling copy when [me]
  /// shared the value, else the record the CK was conveyed under.
  static AtKey openableConveyanceKeyFor(
      AtKey value, String ckKid, String ckNs, String? me) {
    final sharedWith = value.sharedWith;
    final sharedOut = me != null &&
        value.sharedBy == me &&
        sharedWith != null &&
        sharedWith.isNotEmpty &&
        sharedWith != me;
    return sharedOut
        ? ckSiblingCopyKey(sender: me, ckKid: ckKid, ckNs: ckNs)
        : conveyanceKeyFor(value, ckKid, ckNs);
  }

  /// The CK cache's scope: whose nskey the CK was conveyed under. On an inbound
  /// value this is the recipient, matching how the conveyance was cached.
  static String _nskeyOwnerOf(AtKey atKey) {
    final owner = atKey.sharedWith ?? atKey.sharedBy;
    if (owner == null || owner.isEmpty) {
      throw AtKeyException('a data value must carry sharedBy');
    }
    return owner;
  }

  static String _namespaceOf(AtKey atKey) {
    final namespace = atKey.namespace;
    if (namespace == null || namespace.isEmpty) {
      throw AtKeyException('a data value must carry a namespace');
    }
    return namespace;
  }
}
