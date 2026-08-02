import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_commons/at_commons.dart';

/// Wire id of the CK-conveyance provider.
///
/// The id names the **role** (`at/nskey`) and then every algorithm a reader
/// needs code for: the KEM the content key is encapsulated under, and the AEAD
/// wrapping it inside the `pqSeal` envelope. Anything a reader can discover from
/// the value itself — the envelope version, `ckKid`, `nskeyKid` — stays out.
///
/// That is what makes an algorithm change graceful rather than a flag day: a
/// reader registers every scheme it supports, values route by their own id so
/// old ones never stop opening, and a writer can *decide* whether a recipient
/// can read a scheme instead of guessing. A future
/// `at/nskey/MLKEM1024/AES/GCM` coexists with this one.
const String nskeyCryptoProviderId = 'at/nskey/XWING/AES/GCM';

/// The role prefix every CK-conveyance scheme shares, whatever its algorithms.
const String nskeyProviderFamily = 'at/nskey';

/// Which key class a CK was sealed to.
///
/// Cold-start is **not** a third provider id — a CK sealed to the atSign-level
/// root key is still an `at/nskey` record, distinguished only by this field.
class NskeyRecipientKind {
  /// The `(atSign, namespace)` nskey — the steady-state target for both the
  /// owner's own CKs and inbound ones.
  static const String nskey = 'nskey';

  /// `public:pqpublickey@<recipient>` — the cold-start target, used when the
  /// recipient's namespace has no published nskey yet.
  static const String rootPqpublickey = 'root-pqpublickey';
}

/// Layer 2 of the nskey data path: conveys a symmetric content key.
///
/// A value routed here **is** a sealed CK — the `<ckKid>.__ck.<ns>@<owner>`
/// record. [encrypt] takes the CK's base64 bytes and returns the X-Wing
/// `pqSeal` envelope; [decrypt] opens it with the namespace's nskey private and
/// caches the CK, so the `at/symmetric/AES/GCM` provider can resolve it by
/// `ckKid` when the data value arrives.
///
/// Application data never passes through this provider — an nskey encapsulates
/// content keys and nothing else.
class NskeyProvider implements CryptoProvider, HandlesSelectively {
  final NskeyKeyRing keyRing;
  final ContentKeyCache cache;
  final AtKemAlgorithm _xwing;

  NskeyProvider({
    required this.keyRing,
    required this.cache,
    AtKemAlgorithm? xwing,
  }) : _xwing = xwing ?? XWingPureDartAlgo.instance;

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
  String get id => nskeyCryptoProviderId;

  /// Binds the HPKE key schedule to the conveyance's owner and namespace, so an
  /// envelope sealed for one namespace cannot be opened as another's.
  static Uint8List _info(String owner, String namespace) => Uint8List.fromList(
      utf8.encode('$nskeyCryptoProviderId:$owner:$namespace'));

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String plaintext) async {
    final nskeyOwner = _nskeyOwnerOf(atKey);
    final namespace = _namespaceOf(atKey);

    final advertised = await keyRing.currentPublic(nskeyOwner, namespace);
    if (advertised == null) {
      throw AtEncryptionException(
          'no nskey published for $nskeyOwner:$namespace — under eager '
          'publication that means the namespace has never been used, so this is '
          'the cold-start case; sealing to public:pqpublickey is not yet wired');
    }

    final ck = ContentKey.fromBase64(plaintext);
    final envelope = await pqSeal(
      _xwing,
      advertised.publicKey,
      ck.bytes,
      info: _info(_recordOwnerOf(atKey), namespace),
    );

    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'recipientKind': NskeyRecipientKind.nskey,
        'ckKid': ck.ckKid,
        'nskeyKid': advertised.nskeyKid,
      },
    );

    // Cache on write too: the writer encrypts subsequent data values under this
    // CK without re-opening its own conveyance record. This is the one place a
    // CK becomes *current* — the client that cut it says so.
    cache.putAsCurrent(nskeyOwner, namespace, ck, advertised.nskeyKid);

    return base64Encode(envelope);
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    final nskeyOwner = _nskeyOwnerOf(atKey);
    final namespace = _namespaceOf(atKey);

    final nskeyKid = atKey.metadata.appMetadata?.additional?['nskeyKid'];
    if (nskeyKid is! String) {
      throw AtDecryptionException(
          'an $nskeyCryptoProviderId record must name the nskey generation it '
          'was sealed to in appMetadata.nskeyKid');
    }

    final private = await keyRing.privateHalf(nskeyOwner, namespace, nskeyKid);
    if (private == null) {
      throw AtDecryptionException(
          'no nskey private held for $nskeyOwner:$namespace generation '
          '$nskeyKid — this client is not authorised for the namespace, or has '
          'not yet received that generation');
    }

    final Uint8List ckBytes;
    try {
      ckBytes = await pqOpen(
        _xwing,
        private,
        Uint8List.fromList(base64Decode(ciphertext)),
        info: _info(_recordOwnerOf(atKey), namespace),
      );
    } on PqOpenException catch (e) {
      throw AtDecryptionException('could not decapsulate the content key: $e');
    } on ArgumentError catch (e) {
      // pqOpen documents PqOpenException, but its KEM decapsulate call sits
      // outside that guard, so a wrong-length envelope escapes as a raw
      // ArgumentError. Keep the provider's contract whatever the envelope is.
      throw AtDecryptionException('malformed at/nskey envelope: $e');
    } on FormatException catch (e) {
      throw AtDecryptionException('at/nskey value is not valid base64: $e');
    }

    // Cache, but do not make current: sync is unordered, so this conveyance may
    // be older than the CK new writes are already using.
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
