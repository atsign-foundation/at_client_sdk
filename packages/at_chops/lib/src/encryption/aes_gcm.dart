import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/at_iv.dart';
import 'package:at_chops/src/secure_random.dart';
import 'package:at_commons/at_commons.dart';
import 'package:pointycastle/api.dart'
    show AEADParameters, InvalidCipherTextException, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

/// AES-256-GCM authenticated encryption (AEAD), backed by pure-Dart
/// pointycastle.
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

  AesGcm256EncryptionAlgo();

  /// GCM appends the [tagLength]-byte tag on encryption and strips-and-checks
  /// it on decryption, which is the `ciphertext || tag` wire format already.
  GCMBlockCipher _cipher(
          bool forEncryption, Uint8List key, Uint8List nonce, List<int> aad) =>
      GCMBlockCipher(AESEngine())
        ..init(
            forEncryption,
            AEADParameters(KeyParameter(key), tagLength * 8, nonce,
                Uint8List.fromList(aad)));

  @override
  String get name => EncryptionAlgoType.aesgcm256.name;

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
    return _cipher(true, key, iv.ivBytes, aad).process(plainData);
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
    try {
      return _cipher(false, key, iv.ivBytes, aad).process(encryptedData);
    } on InvalidCipherTextException {
      throw AtDecryptionException(
          'AES-256-GCM authentication failed: data was tampered with or the '
          'wrong key/nonce was used');
    }
  }
}
