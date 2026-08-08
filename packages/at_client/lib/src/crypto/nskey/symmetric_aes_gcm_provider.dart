import 'dart:convert';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart' show visibleForTesting;

/// Wire id of the application-data provider.
///
/// This names the *algorithm* deliberately — it is the layer that needs
/// crypto-agility. A future `at/symmetric/AES/SIV` coexists with it, and values
/// written under this id keep their tag forever.
const String symmetricAesGcmCryptoProviderId = 'at/symmetric/AES/GCM';

/// The value cites a CK this client cannot resolve *yet*.
///
/// Distinct from a hard decryption failure on purpose: sync is unordered, so a
/// data value routinely arrives before the conveyance record carrying its CK.
/// A caller seeing this should re-attempt the read once the conveyance syncs —
/// where a plain [AtDecryptionException] means give up. A CK deleted for
/// forward secrecy also surfaces here, and stays unresolvable by design.
class ContentKeyUnavailableException extends AtDecryptionException {
  /// The kid the value cited, as it appears in `appMetadata`.
  final String ckKid;

  ContentKeyUnavailableException(this.ckKid, String message) : super(message);
}

/// Layer 3 of the nskey data path: application data, AES-256-GCM under a
/// content key.
///
/// Purely symmetric — it never touches asymmetric crypto. A value carries its
/// ciphertext and *cites* a CK by `ckKid`; no sealed key is inline. The CK is
/// resolved from the [ContentKeyCache], which the `at/nskey` provider populates
/// when the matching conveyance record syncs.
class SymmetricAesGcmProvider
    implements
        CryptoProvider,
        PreparesWrites,
        HandlesSelectively,
        ReportsReadiness {
  final ContentKeyCache cache;

  /// Mints and conveys a content key when a destination has none, or when the
  /// one in hand was sealed to a generation the destination has rotated away
  /// from. Null leaves the caller responsible for conveying a CK first, which
  /// is the shape the tests drive the providers in.
  final CkManager? ckManager;

  SymmetricAesGcmProvider({required this.cache, this.ckManager});

  /// The nskey data path is scoped to `(owner, namespace)` throughout — the key
  /// ring, the CK cache and the HPKE binding all take a namespace — so a key
  /// without one cannot be served here at all.
  ///
  /// A `local:` key is declined too, for a different reason: it never syncs and
  /// is never shared, so encrypting it under a content key that is itself
  /// conveyed by a *synced* record would make device-local state depend on a
  /// mechanism built for data that leaves the device. Local state stays on the
  /// self-encryption path.
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
  /// before writing costs nothing extra — and the freshness window means a
  /// "yes" here is as current as the write's own would be.
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
    // Where the nskey — and therefore the content key — actually lives. For a
    // flat namespace this is `namespace` itself; for a composed one it is
    // whichever level the walk landed on.
    final ckNs = await _ckNamespaceOf(owner, namespace);

    final ck = cache.current(owner, ckNs);
    if (ck == null) {
      throw AtEncryptionException(
          'no content key established for $owner:$ckNs — convey a CK via '
          'an $nskeyCryptoProviderId record before writing data');
    }

    // A fresh 12-byte nonce per value — never reuse a (key, nonce) pair.
    final iv = InitialisationVector.random(AesGcm256EncryptionAlgo.nonceLength);
    final ciphertext = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64()))
        .encrypt(_toBytes(atKey, plaintext), iv: iv, aad: _aad(atKey));

    // The runtime re-stamps providerId after this returns; setting it here just
    // keeps the record self-describing for callers that drive the provider
    // directly. `additional` is the part only this provider can supply.
    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'ckKid': ck.ckKid,
        'iv': base64Encode(iv.ivBytes),
        // The record's own namespace, which no reader can recover from the
        // wire string: AtKey.fromString splits at the last dot, so a
        // multi-segment namespace is unrecoverable. Already plaintext in the
        // key name, so this discloses nothing new.
        'ns': namespace,
        // And where its content key lives, which differs whenever resolution
        // walked up. Without it a reader would hunt for the conveyance at the
        // wrong level and report "not yet synced" for an intact record.
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

    // The record says where its content key lives; falling back to the key's
    // own namespace keeps a flat record readable if the field is absent.
    final namespace = additional['ckNs'] as String? ?? _namespaceOf(atKey);

    final ckKid = additional['ckKid'];
    final ivB64 = additional['iv'];
    if (ckKid is! String || ivB64 is! String) {
      throw AtDecryptionException(
          'an $symmetricAesGcmCryptoProviderId value must carry ckKid and iv '
          'in appMetadata');
    }

    final ck = cache.get(owner, namespace, ckKid) ??
        await _resolveFromLocalConveyance(
            context, atKey, owner, namespace, ckKid);
    if (ck == null) {
      throw ContentKeyUnavailableException(
          ckKid,
          'content key $ckKid not yet available for $owner:$namespace — its '
          'conveyance record has not synced, or the key was rotated away');
    }

    final plain = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64())).decrypt(
      Uint8List.fromList(base64Decode(ciphertext)),
      iv: InitialisationVector(Uint8List.fromList(base64Decode(ivB64))),
      aad: _aad(atKey),
    );
    return _fromBytes(atKey, plain);
  }

  /// Binds a value's ciphertext to the record it was written under.
  ///
  /// A content key is scoped to `(nskey owner, namespace)` and covers many
  /// records, so the key alone says nothing about *which* record a ciphertext
  /// belongs to. Without this, anyone who can write the store — an atServer
  /// operator, or a sync path — can move a valid ciphertext from one record to
  /// another in the same scope and it still authenticates: yesterday's `no`
  /// reappears as today's `yes`, with the AEAD tag intact.
  ///
  /// The HPKE `info` at layer 2 binds the *conveyance* to its owner and
  /// namespace; it does not reach the values. This is the equivalent binding
  /// one layer down, over the record's full address.
  ///
  /// Composed from the AtKey's fields rather than `toString()` deliberately:
  /// the writer and the reader must derive byte-identical AAD or nothing
  /// decrypts, and the field accessors are stable where the string form varies
  /// with `cached:`/`public:` prefixes and metadata state.
  ///
  /// The name and namespace are joined back together rather than bound as two
  /// fields, because *where* they split is not stable: `AtKey.fromString` cuts
  /// at the last dot, so a reader that parsed the key from the wire sees
  /// `someid.d.c.b` + `a` where the writer had `someid` + `d.c.b.a`. Two fields
  /// would disagree; the joined name is identical either way, and it is the
  /// record's actual address — which is what this is binding.
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
  /// namespace, which is the shape the provider-level tests drive.
  Future<String> _ckNamespaceOf(String owner, String namespace) async =>
      (await ckManager?.resolver.resolve(owner, namespace))?.namespace ??
      namespace;

  /// Second chance on a cache miss: the conveyance record may already be in
  /// local storage, just never opened by this process. Reading it routes back
  /// through the `at/nskey` provider, which decapsulates and caches as a side
  /// effect — so the CK is looked up again rather than taken from the read.
  ///
  /// A record that simply is not there is not an error — that is the ordinary
  /// out-of-order-sync case, and the caller retries. A record that *is* there
  /// and will not open is the opposite, and is re-thrown: a failed AEAD, a
  /// malformed envelope or a kid collision means tampering or corruption, and
  /// this is the only place the key layer can raise that alarm. Reporting it
  /// as "not yet synced" would hide it behind advice to keep polling.
  Future<ContentKey?> _resolveFromLocalConveyance(
    CryptoContext context,
    AtKey value,
    String owner,
    String namespace,
    String ckKid,
  ) async {
    try {
      await context.atClient.get(conveyanceKeyFor(value, ckKid, namespace));
    } on AtDecryptionException {
      rethrow;
    } on StateError {
      // ContentKeyCache.put refuses two distinct CKs claiming one kid.
      rethrow;
    } catch (_) {
      return null;
    }
    return cache.get(owner, namespace, ckKid);
  }

  /// The at-key the CK for [value] was conveyed under.
  ///
  /// A conveyance mirrors the value's own addressing —
  /// `<ckKid>.__ck.<ckNs>@<owner>` for self data,
  /// `@<recipient>:<ckKid>.__ck.<ckNs>@<sender>` for a share. Deriving it from
  /// the value rather than from the nskey owner alone is what keeps the inbound
  /// case addressable, since there sender and recipient are different atSigns.
  ///
  /// [ckNs] is the namespace the nskey resolved to, **not** the value's own. One
  /// conveyance therefore serves every namespace beneath it — which is what
  /// makes an AtCollection sub-collection viable, since its namespace carries a
  /// per-item id and would otherwise need a conveyance record per item.
  static AtKey conveyanceKeyFor(AtKey value, String ckKid, String ckNs) =>
      AtKey()
        ..key = '$ckKid.__ck'
        ..namespace = ckNs
        ..sharedBy = value.sharedBy
        ..sharedWith = value.sharedWith
        ..metadata = Metadata();

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
