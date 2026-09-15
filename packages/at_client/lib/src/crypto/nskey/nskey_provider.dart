import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/pq_envelope.dart'
    show pqOpenFromBase64, pqSealToBase64;
import 'package:at_commons/at_commons.dart';

/// The provider id that conveys a content key sealed to a [keyAlgo] nskey, or
/// null for an algorithm this build cannot seal to.
String? nskeyProviderIdFor(String keyAlgo) => switch (keyAlgo) {
      SecretSharingAlgos.xWing => nskeyCryptoProviderId,
      SecretSharingAlgos.mlKem1024 => mlKemNskeyCryptoProviderId,
      _ => null,
    };

/// Which key class a CK was sealed to.
///
/// There is only one, and the field exists so a future one can be told apart on
/// a record already written. It is deliberately *not* a second provider id: an
/// alternative recipient class would still be an `at/nskey` conveyance.
///
/// The atSign-level `public:pq_signing_root@<atSign>` is **not** a member and
/// never will be. It is a signing root — ML-DSA-65, a verification key with no
/// encapsulation capability — so there is nothing to seal to it. Cold start
/// therefore has no PQ target at all, which is the design's intent rather than
/// a gap; see [NskeyProvider.encrypt].
class NskeyRecipientKind {
  /// The `(atSign, namespace)` nskey — the steady-state target for both the
  /// owner's own CKs and inbound ones.
  static const String nskey = 'nskey';
}

/// [atSign] has no published nskey for [namespace], so nothing can be sealed to
/// it under the post-quantum path.
///
/// Distinct from every other encryption failure because it is not one: nothing
/// went wrong, this client found no nskey published for the namespace. An app
/// that catches this can tell its user *"@bob hasn't enabled this yet"* instead
/// of surfacing an encryption error for a situation neither side has done
/// anything wrong in.
///
/// ⚠️ **It means "not found now", not "never published"** — it is raised only
/// after a probe that found nothing, never on the strength of a remembered
/// miss. [CryptoRuntime.isReadyFor] asks the same question ahead of composing
/// anything, and is as current as this is.
///
/// There is no post-quantum fallback to offer: the only atSign-level key is a
/// signing root, which cannot receive an encapsulation. The escape hatch is the
/// legacy path, and it is opt-in
/// ([AtClientPreference.allowLegacyCryptoFallback]) because a silent downgrade
/// to RSA is exactly what this design exists to stop.
class NamespaceKeyUnavailableException extends AtEncryptionException {
  /// The atSign whose namespace key is missing — the recipient for a share, or
  /// the writer for self data.
  final String atSign;

  final String namespace;

  NamespaceKeyUnavailableException(this.atSign, this.namespace)
      : super('$atSign has no published nskey for "$namespace" — that '
            'namespace has not been used or authorised there, so there is no '
            'post-quantum key to seal a content key to. Reaching it needs the '
            'legacy path, which must be opted into explicitly.');
}

/// Layer 2 of the nskey data path: conveys a symmetric content key.
///
/// A value routed here **is** a sealed CK — the `<ckKid>.__ck.<ns>@<owner>`
/// record. [encrypt] takes the CK's base64 bytes and returns the `pqSeal`
/// envelope; [decrypt] opens it with the namespace's nskey private and
/// caches the CK, so the `at/symmetric/AES/GCM` provider can resolve it by
/// `ckKid` when the data value arrives.
///
/// Application data never passes through this provider — an nskey encapsulates
/// content keys and nothing else.
class NskeyProvider implements CryptoProvider, HandlesSelectively {
  final NskeyKeyRing keyRing;
  final ContentKeyCache cache;

  /// The key-establishment algorithm this instance conveys under. One instance
  /// per KEM, each with its own [id], so a record routes back to the one that
  /// can open it.
  final String keyAlgo;

  final AtKemAlgorithm _kem;

  NskeyProvider({
    required this.keyRing,
    required this.cache,
    this.keyAlgo = SecretSharingAlgos.xWing,
    AtKemAlgorithm? kem,
  }) : _kem = kem ??
            SecretSharingAlgos.kemFor(keyAlgo) ??
            XWingPureDartAlgo.instance;

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
  String get id => nskeyProviderIdFor(keyAlgo) ?? nskeyCryptoProviderId;

  /// The strongest `pqSeal` construction both this provider and the
  /// destination can handle, or null if there is no overlap.
  ///
  /// No overlap is a refusal, not a fallback to this build's preference: the
  /// owner would get a conveyance it cannot unwrap, and the failure would
  /// surface on their side as an AEAD error naming nothing.
  int? _sealVersionFor(NskeyAdvertisement advertised) {
    final suite = SecretSharingAlgos.bestSuiteBetween(
        SecretSharingAlgos.openableSuitesFor(keyAlgo), advertised.suites);
    return suite == null ? null : SecretSharingAlgos.sealVersionFor(suite);
  }

  /// The label the conveyance's HPKE key schedule binds, ahead of the record's
  /// sender and namespace.
  ///
  /// Names the role and nothing else — RFC 9180 folds `suite_id` (KEM, KDF and
  /// AEAD) into every label the schedule derives, so suites stay separated
  /// without help — and it is its own constant rather than a provider id, so
  /// that renaming a routing string cannot rewrite a key schedule.
  static const String _infoLabel = 'at/nskey';

  /// Binds the HPKE key schedule to the record's sender and namespace, so an
  /// envelope sealed for one namespace cannot be opened as another's.
  static Uint8List _info(String sharedBy, String namespace) =>
      Uint8List.fromList(utf8.encode('$_infoLabel:$sharedBy:$namespace'));

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String plaintext) async {
    final nskeyOwner = _nskeyOwnerOf(atKey);
    final namespace = _namespaceOf(atKey);

    final advertised = await keyRing.currentPublic(nskeyOwner, namespace);
    if (advertised == null) {
      throw NamespaceKeyUnavailableException(nskeyOwner, namespace);
    }

    final ck = ContentKey.fromBase64(plaintext);

    // NOTE: seal to the ENTRY under this provider's own KEM, never to
    // `NskeyAdvertisement.alg`/`.publicKey`/`.nskeyKid` — those answer for a
    // single entry, so on an advertisement carrying two they encapsulate to the
    // wrong key and stamp a kid the owner never looks for.
    final entry = advertised.usableFor([keyAlgo]);
    if (entry == null) {
      throw AtEncryptionException('$nskeyOwner:$namespace advertises '
          '${advertised.keys.map((k) => k.alg).toSet().join(', ')}, '
          'and $id can only seal to $keyAlgo');
    }
    final int? version = _sealVersionFor(advertised);
    if (version == null) {
      throw AtEncryptionException(
          '$nskeyOwner:$namespace advertises a ${entry.alg} nskey opening '
          '${advertised.suites}, and $id produces '
          '${SecretSharingAlgos.openableSuitesFor(keyAlgo)} — no shared '
          'construction, so nothing is sealed rather than sealing something '
          'they cannot open');
    }
    // NOTE: this binding must stay distinct from the pairwise substrate's, or
    // an envelope from one could be opened as the other's.
    final String envelope = await pqSealToBase64(
      _kem,
      entry.pubBytes,
      ck.bytes,
      info: _info(_recordOwnerOf(atKey), namespace),
      version: version,
    );

    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'recipientKind': NskeyRecipientKind.nskey,
        'ckKid': ck.ckKid,
        'nskeyKid': entry.kid,
        // NOTE: no reader can recover the namespace the nskey resolved to from
        // the wire string — AtKey.fromString cuts at the last dot, so
        // `<ckKid>.__ck.app_1.my_apps` parses back as `my_apps`.
        'ns': namespace,
      },
    );

    // NOTE: cached but deliberately not made current — this runs inside the put
    // transformer, with the write still to come, so promoting a CK whose
    // conveyance never reaches storage leaves `CkManager.ensureCurrent`
    // skipping it forever. The manager promotes it once the write returns.
    cache.put(nskeyOwner, namespace, ck);

    return envelope;
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    final nskeyOwner = _nskeyOwnerOf(atKey);
    final additional = atKey.metadata.appMetadata?.additional;
    // NOTE: the record states its own namespace, because a conveyance key
    // re-parsed from the wire mis-splits a multi-segment one — both the private
    // lookup and the HPKE binding would then be wrong.
    final namespace = additional?['ns'] as String? ?? _namespaceOf(atKey);

    final nskeyKid = additional?['nskeyKid'];
    if (nskeyKid is! String) {
      throw AtDecryptionException(
          'an $nskeyCryptoProviderId record must name the nskey generation it '
          'was sealed to in appMetadata.nskeyKid');
    }

    final private = await keyRing.privateHalf(nskeyOwner, namespace, nskeyKid);
    if (private == null) {
      // NOTE: the notification service parks on this type and re-drives it when
      // the private is filed, so the retry must not depend on the wording.
      throw NskeyPrivateUnavailableException(
          nskeyOwner,
          namespace,
          nskeyKid,
          'this client is not authorised for the namespace, or has not yet '
          'received that generation');
    }

    final Uint8List ckBytes;
    try {
      ckBytes = await pqOpenFromBase64(
        _kem,
        private.bytes,
        ciphertext,
        info: _info(_recordOwnerOf(atKey), namespace),
      );
    } on PqOpenException catch (e) {
      throw AtDecryptionException('could not decapsulate the content key: $e');
    } on ArgumentError catch (e) {
      // NOTE: a stray ArgumentError must still surface as a decryption failure
      // rather than escaping as a raw error.
      throw AtDecryptionException('malformed at/nskey envelope: $e');
    }

    // NOTE: cached but not made current — sync is unordered, so this conveyance
    // may be older than the CK new writes are already using.
    final ck = ContentKey(ckBytes);
    cache.put(nskeyOwner, namespace, ck);
    return ck.toBase64();
  }

  /// Who owns the *record* — what the HPKE `info` binds, so an envelope sealed
  /// for one sender cannot be reinterpreted as another's under the same nskey.
  static String _recordOwnerOf(AtKey atKey) {
    final owner = atKey.sharedBy;
    if (owner == null || owner.isEmpty) {
      throw AtKeyException('an at/nskey record must carry sharedBy');
    }
    return owner;
  }

  /// Whose *nskey* seals or opens it, and the CK cache's scope. On an inbound
  /// record this is the recipient, not the sender that owns the record — reading
  /// the ring by `sharedBy` is why cross-atSign reads would fail.
  static String _nskeyOwnerOf(AtKey atKey) =>
      atKey.sharedWith ?? _recordOwnerOf(atKey);

  static String _namespaceOf(AtKey atKey) {
    final namespace = atKey.namespace;
    if (namespace == null || namespace.isEmpty) {
      throw AtKeyException('an at/nskey record must carry a namespace');
    }
    return namespace;
  }
}
