import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_commons/at_commons.dart';

/// Wire id of the application-data provider.
///
/// This names the *algorithm* deliberately — it is the layer that needs
/// crypto-agility. A future `at/symmetric/AES/SIV` coexists with it, and values
/// written under this id keep their tag forever.
const String symmetricAesGcmCryptoProviderId = 'at/symmetric/AES/GCM';

/// Layer 3 of the nskey data path: application data, AES-256-GCM under a
/// content key.
///
/// Purely symmetric — it never touches asymmetric crypto. A value carries its
/// ciphertext and *cites* a CK by `ckKid`; no sealed key is inline. The CK is
/// resolved from the [ContentKeyCache], which the `at/nskey` provider populates
/// when the matching conveyance record syncs.
class SymmetricAesGcmProvider implements CryptoProvider {
  final ContentKeyCache cache;

  SymmetricAesGcmProvider({required this.cache});

  @override
  String get id => symmetricAesGcmCryptoProviderId;

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String plaintext) async {
    final owner = _ownerOf(atKey);
    final namespace = _namespaceOf(atKey);

    final ck = cache.current(owner, namespace);
    if (ck == null) {
      throw AtEncryptionException(
          'no content key established for $owner:$namespace — convey a CK via '
          'an $nskeyProviderHint record before writing data');
    }

    // A fresh 12-byte nonce per value — never reuse a (key, nonce) pair.
    final iv =
        InitialisationVector.random(AesGcm256EncryptionAlgo.nonceLength);
    final ciphertext = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64()))
        .encrypt(Uint8List.fromList(utf8.encode(plaintext)), iv: iv);

    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'ckKid': ck.ckKid,
        'iv': base64Encode(iv.ivBytes),
      },
    );

    return base64Encode(ciphertext);
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    final owner = _ownerOf(atKey);
    final namespace = _namespaceOf(atKey);
    final additional = atKey.metadata.appMetadata?.additional ?? const {};

    final ckKid = additional['ckKid'];
    final ivB64 = additional['iv'];
    if (ckKid is! String || ivB64 is! String) {
      throw AtDecryptionException(
          'an $symmetricAesGcmCryptoProviderId value must carry ckKid and iv '
          'in appMetadata');
    }

    final ck = cache.get(owner, namespace, ckKid);
    if (ck == null) {
      // Sync is not ordered, so a data value can arrive before its conveyance
      // record. This is the deferred case, not a hard failure: the read is
      // re-attempted once the CK arrives. A CK deleted for forward secrecy
      // stays unresolvable by design.
      throw AtDecryptionException(
          'content key $ckKid not yet available for $owner:$namespace — its '
          'conveyance record has not synced, or the key was rotated away');
    }

    final plain = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64())).decrypt(
      Uint8List.fromList(base64Decode(ciphertext)),
      iv: InitialisationVector(Uint8List.fromList(base64Decode(ivB64))),
    );
    return utf8.decode(plain);
  }

  static const String nskeyProviderHint = 'at/nskey';

  static String _ownerOf(AtKey atKey) {
    final owner = atKey.sharedBy;
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
