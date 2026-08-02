import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_commons/at_commons.dart';

/// Wire id of the CK-conveyance provider.
const String nskeyCryptoProviderId = 'at/nskey';

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
class NskeyProvider implements CryptoProvider {
  final NskeyKeyRing keyRing;
  final ContentKeyCache cache;
  final AtKemAlgorithm _xwing;

  NskeyProvider({
    required this.keyRing,
    required this.cache,
    AtKemAlgorithm? xwing,
  }) : _xwing = xwing ?? XWingPureDartAlgo.instance;

  @override
  String get id => nskeyCryptoProviderId;

  /// Binds the HPKE key schedule to the conveyance's owner and namespace, so an
  /// envelope sealed for one namespace cannot be opened as another's.
  static Uint8List _info(String owner, String namespace) => Uint8List.fromList(
      utf8.encode('$nskeyCryptoProviderId:$owner:$namespace'));

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String plaintext) async {
    final owner = _ownerOf(atKey);
    final namespace = _namespaceOf(atKey);

    final recipientPublic = await keyRing.publicHalf(owner, namespace);
    if (recipientPublic == null) {
      throw AtEncryptionException(
          'no nskey published for $owner:$namespace — cold-start sealing to '
          'public:pqpublickey is not yet wired');
    }

    final ck = ContentKey.fromBase64(plaintext);
    final envelope = await pqSeal(
      _xwing,
      recipientPublic,
      ck.bytes,
      info: _info(owner, namespace),
    );

    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'recipientKind': NskeyRecipientKind.nskey,
        'ckKid': ck.ckKid,
      },
    );

    // Cache on write too: the writer encrypts subsequent data values under this
    // CK without re-opening its own conveyance record. This is the one place a
    // CK becomes *current* — the client that cut it says so.
    cache.putAsCurrent(owner, namespace, ck);

    return base64Encode(envelope);
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    final owner = _ownerOf(atKey);
    final namespace = _namespaceOf(atKey);

    final private = await keyRing.privateHalf(owner, namespace);
    if (private == null) {
      throw AtDecryptionException(
          'no nskey private held for $owner:$namespace — this client is not '
          'authorised for the namespace, or has not yet received the key');
    }

    final Uint8List ckBytes;
    try {
      ckBytes = await pqOpen(
        _xwing,
        private,
        Uint8List.fromList(base64Decode(ciphertext)),
        info: _info(owner, namespace),
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
    cache.put(owner, namespace, ck);
    return ck.toBase64();
  }

  static String _ownerOf(AtKey atKey) {
    final owner = atKey.sharedBy;
    if (owner == null || owner.isEmpty) {
      throw AtKeyException('an at/nskey record must carry sharedBy');
    }
    return owner;
  }

  static String _namespaceOf(AtKey atKey) {
    final namespace = atKey.namespace;
    if (namespace == null || namespace.isEmpty) {
      throw AtKeyException('an at/nskey record must carry a namespace');
    }
    return namespace;
  }
}
