import 'dart:typed_data';

import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/at_iv.dart';
import 'package:at_chops/src/secure_random.dart';
import 'package:at_commons/at_commons.dart';
import 'package:cryptography/cryptography.dart' as crypto;

/// AES-256-GCM authenticated encryption (AEAD), backed by pure-Dart
/// (`package:cryptography`).
///
/// Unlike [AesCtrEncryptionAlgo] (AES-CTR, unauthenticated), GCM output is
/// authenticated: tampering with the ciphertext, tag or nonce makes
/// [decrypt] throw [AtDecryptionException] instead of returning garbage.
///
/// Wire format: `ciphertext || tag(16)`. The 12-byte nonce is NOT included;
/// callers convey it alongside (e.g. in metadata), exactly as with the
/// existing CTR IVs. Generate one per encryption with
/// `InitialisationVector.random(12)` — never reuse a (key, nonce) pair.
///
/// An optional [aad] (associated data) may be supplied: it is authenticated
/// but NOT encrypted, and must be byte-identical at [encrypt] and [decrypt]
/// or authentication fails. It defaults to empty, so callers that don't use
/// AAD are unaffected.
final class AesGcm256EncryptionAlgo implements SymmetricEncryptionAlgorithm {
  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  static final crypto.AesGcm _aesGcm = crypto.AesGcm.with256bits();

  AesGcm256EncryptionAlgo();

  /// Generate a fresh [keyLength]-byte AES-256 key.
  @override
  Uint8List generateKey() => secureRandomBytes(keyLength);

  @override
  Future<Uint8List> encrypt(Uint8List plainData, Uint8List key,
      {required InitialisationVector iv, List<int> aad = const []}) async {
    if (key.length != keyLength) {
      throw AtEncryptionException(
          'AES-256-GCM requires a 256-bit key; got ${key.length * 8} bits');
    }
    if (iv.ivBytes.length != nonceLength) {
      throw AtEncryptionException(
          'AES-256-GCM requires a $nonceLength-byte nonce; '
          'use InitialisationVector.random($nonceLength)');
    }
    final crypto.SecretBox box = await _aesGcm.encrypt(
      plainData,
      secretKey: crypto.SecretKey(key),
      nonce: iv.ivBytes.toList(),
      aad: aad,
    );
    return Uint8List.fromList(box.cipherText + box.mac.bytes);
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData, Uint8List key,
      {required InitialisationVector iv, List<int> aad = const []}) async {
    if (key.length != keyLength) {
      throw AtDecryptionException(
          'AES-256-GCM requires a 256-bit key; got ${key.length * 8} bits');
    }
    if (iv.ivBytes.length != nonceLength) {
      throw AtDecryptionException(
          'AES-256-GCM requires a $nonceLength-byte nonce; '
          'use InitialisationVector.random($nonceLength)');
    }
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
            nonce: iv.ivBytes.toList(), mac: crypto.Mac(tag)),
        secretKey: crypto.SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw AtDecryptionException(
          'AES-256-GCM authentication failed: data was tampered with or the '
          'wrong key/nonce was used');
    }
  }
}
