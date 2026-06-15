import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_commons/at_commons.dart';
import 'package:cryptography/cryptography.dart' as crypto;

/// AES-256-GCM authenticated encryption (AEAD), backed by pure-Dart
/// (`package:cryptography`).
///
/// Unlike [AESEncryptionAlgo] (AES-CTR, unauthenticated), GCM output is
/// authenticated: tampering with the ciphertext, tag or nonce makes
/// [decrypt] throw [AtDecryptionException] instead of returning garbage.
///
/// Wire format: `ciphertext || tag(16)`. The 12-byte nonce is NOT included;
/// callers convey it alongside (e.g. in metadata), exactly as with the
/// existing CTR IVs. Generate one per encryption with
/// `AtChopsUtil.generateRandomIV(12)` — never reuse a (key, nonce) pair.
final class AesGcm256EncryptionAlgo
    implements SymmetricEncryptionAlgorithm<Uint8List, Uint8List> {
  static const int nonceLength = 12;
  static const int tagLength = 16;

  static final crypto.AesGcm _aesGcm = crypto.AesGcm.with256bits();

  final AESKey _aesKey;

  AesGcm256EncryptionAlgo(this._aesKey);

  @override
  Future<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv}) async {
    final crypto.SecretBox box = await _aesGcm.encrypt(
      plainData,
      secretKey: crypto.SecretKey(_keyBytes()),
      nonce: _nonceBytes(iv),
    );
    return Uint8List.fromList(box.cipherText + box.mac.bytes);
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData,
      {InitialisationVector? iv}) async {
    if (encryptedData.length < tagLength) {
      throw AtDecryptionException(
          'AES-256-GCM input shorter than the $tagLength-byte tag');
    }
    final Uint8List cipherText =
        encryptedData.sublist(0, encryptedData.length - tagLength);
    final Uint8List tag =
        encryptedData.sublist(encryptedData.length - tagLength);
    try {
      final List<int> plain = await _aesGcm.decrypt(
        crypto.SecretBox(cipherText,
            nonce: _nonceBytes(iv), mac: crypto.Mac(tag)),
        secretKey: crypto.SecretKey(_keyBytes()),
      );
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw AtDecryptionException(
          'AES-256-GCM authentication failed: data was tampered with or the '
          'wrong key/nonce was used');
    }
  }

  Uint8List _keyBytes() {
    // AESKey carries its material base64-encoded, per the at_chops contract.
    final Uint8List keyBytes = base64Decode(_aesKey.key);
    if (keyBytes.length != 32) {
      throw AtEncryptionException(
          'AES-256-GCM requires a 256-bit key; got ${keyBytes.length * 8} bits');
    }
    return keyBytes;
  }

  List<int> _nonceBytes(InitialisationVector? iv) {
    if (iv == null || iv.ivBytes.length != nonceLength) {
      throw AtEncryptionException(
          'AES-256-GCM requires an explicit $nonceLength-byte nonce; '
          'use AtChopsUtil.generateRandomIV($nonceLength)');
    }
    return iv.ivBytes;
  }
}
