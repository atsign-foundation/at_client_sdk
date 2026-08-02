import 'dart:convert';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
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
    final iv = InitialisationVector.random(AesGcm256EncryptionAlgo.nonceLength);
    final ciphertext = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64()))
        .encrypt(_toBytes(atKey, plaintext), iv: iv);

    // The runtime re-stamps providerId after this returns; setting it here just
    // keeps the record self-describing for callers that drive the provider
    // directly. `additional` is the part only this provider can supply.
    atKey.metadata.appMetadata = AppMetadata(
      providerId: id,
      additional: {
        'ckKid': ck.ckKid,
        'iv': base64Encode(iv.ivBytes),
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

    final ck = cache.get(owner, namespace, ckKid) ??
        await _resolveFromLocalConveyance(context, owner, namespace, ckKid);
    if (ck == null) {
      throw ContentKeyUnavailableException(
          ckKid,
          'content key $ckKid not yet available for $owner:$namespace — its '
          'conveyance record has not synced, or the key was rotated away');
    }

    final plain = await AesGcm256EncryptionAlgo(AESKey(ck.toBase64())).decrypt(
      Uint8List.fromList(base64Decode(ciphertext)),
      iv: InitialisationVector(Uint8List.fromList(base64Decode(ivB64))),
    );
    return _fromBytes(atKey, plain);
  }

  /// Second chance on a cache miss: the conveyance record may already be in
  /// local storage, just never opened by this process. Reading it routes back
  /// through the `at/nskey` provider, which decapsulates and caches as a side
  /// effect — so the CK is looked up again rather than taken from the read.
  ///
  /// Failure here is not an error: the record genuinely may not have synced.
  Future<ContentKey?> _resolveFromLocalConveyance(
    CryptoContext context,
    String owner,
    String namespace,
    String ckKid,
  ) async {
    try {
      await context.atClient.get(conveyanceKeyFor(owner, namespace, ckKid));
    } catch (_) {
      return null;
    }
    return cache.get(owner, namespace, ckKid);
  }

  /// The at-key a CK is conveyed under: `<ckKid>.__ck.<ns>@<owner>`.
  static AtKey conveyanceKeyFor(String owner, String namespace, String ckKid) =>
      AtKey()
        ..key = '$ckKid.__ck'
        ..namespace = namespace
        ..sharedBy = owner
        ..metadata = Metadata();

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
