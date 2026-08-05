import 'dart:typed_data';

import 'package:at_chops/src/algo_type.dart';
import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/at_iv.dart';
import 'package:at_chops/src/padding/pkcs7.dart';
import 'package:at_chops/src/padding/types.dart';
import 'package:at_chops/src/secure_random.dart';
import 'package:at_commons/at_commons.dart';
import 'package:better_cryptography/better_cryptography.dart';

/// AES-CTR encryption (unauthenticated), backed by pure-Dart
/// (`package:better_cryptography`).
///
/// The key length is fixed at construction — 16 bytes for AES-128, 24 for
/// AES-192, 32 for AES-256 — and every key passed to [encrypt]/[decrypt] must
/// match it. Keys are raw bytes; if you hold an `AESKey` (which carries its
/// material base64-encoded), pass `base64Decode(aesKey.key)`.
///
/// CTR output is NOT authenticated: tampering with the ciphertext or IV yields
/// garbage plaintext rather than an error. Prefer `AesGcm256EncryptionAlgo` for
/// new data; this class exists for the wire format the Atsign Protocol already
/// has in the field.
///
/// Plaintext is PKCS#7-padded to the 16-byte block size before encryption. The
/// [ivLength]-byte IV is not part of the output; callers convey it alongside
/// (e.g. in metadata) and must pass it explicitly. For data written back when
/// IVs weren't being set, pass [InitialisationVector.legacy].
final class AesCtrEncryptionAlgo implements SymmetricEncryptionAlgorithm {
  /// AES-CTR runs the counter over a full block, so the IV is one block wide.
  static const int ivLength = 16;

  /// The AES key length in bytes this instance is configured for: 16, 24 or 32.
  final int keyLengthBytes;

  final AesCtr _aesCtr;

  @override
  String get name => EncryptionAlgoType.aesctr.name;

  PaddingAlgorithm paddingAlgo = PKCS7Padding(PaddingParams()..blockSize = 16);

  /// Generate a fresh [keyLengthBytes]-byte AES key.
  @override
  Uint8List generateKey() => secureRandomBytes(keyLengthBytes);

  /// Throws [AtEncryptionException] if [keyLengthBytes] is not 16, 24 or 32.
  AesCtrEncryptionAlgo(this.keyLengthBytes)
      : _aesCtr = switch (keyLengthBytes) {
          16 => AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty),
          24 => AesCtr.with192bits(macAlgorithm: MacAlgorithm.empty),
          32 => AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty),
          _ => throw AtEncryptionException(
              'Invalid AES key length $keyLengthBytes. '
              'Valid lengths are 16/24/32 bytes'),
        };

  @override
  Future<Uint8List> encrypt(Uint8List plainData, Uint8List key,
      {required InitialisationVector iv}) async {
    if (key.length != keyLengthBytes) {
      throw AtEncryptionException(
          'Expected a $keyLengthBytes-byte AES key; got ${key.length} bytes');
    }
    if (iv.ivBytes.length != ivLength) {
      throw AtEncryptionException(
          'AES-CTR requires an $ivLength-byte IV; got ${iv.ivBytes.length} bytes');
    }
    final secretKey = await _aesCtr.newSecretKeyFromBytes(key);
    final secretBox = await _aesCtr.encrypt(
      paddingAlgo.addPadding(plainData),
      secretKey: secretKey,
      nonce: iv.ivBytes,
    );
    return Uint8List.fromList(secretBox.cipherText);
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData, Uint8List key,
      {required InitialisationVector iv}) async {
    if (key.length != keyLengthBytes) {
      throw AtDecryptionException(
          'Expected a $keyLengthBytes-byte AES key; got ${key.length} bytes');
    }
    if (iv.ivBytes.length != ivLength) {
      throw AtDecryptionException(
          'AES-CTR requires an $ivLength-byte IV; got ${iv.ivBytes.length} bytes');
    }
    final secretKey = await _aesCtr.newSecretKeyFromBytes(key);
    final decryptedWithPadding = await _aesCtr.decrypt(
      SecretBox(encryptedData, nonce: iv.ivBytes, mac: Mac.empty),
      secretKey: secretKey,
    );
    return Uint8List.fromList(paddingAlgo.removePadding(decryptedWithPadding));
  }
}
