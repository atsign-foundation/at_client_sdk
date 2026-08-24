import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';

import 'aes_gcm.dart';
import 'chacha20_poly1305.dart';

/// An AEAD as the seal path consumes one: raw key, nonce and aad in,
/// `ciphertext || tag` out.
///
/// Package-internal. The exported algorithm classes have per-algorithm call
/// shapes ([AesGcm256EncryptionAlgo] wants an [AESKey] and an
/// [InitialisationVector]); this is the uniform face a ciphersuite can carry,
/// so version dispatch selects a table row instead of naming a class.
abstract interface class AtAeadAlgorithm {
  /// Nonce length in bytes.
  int get nonceLength;

  /// Authentication-tag length in bytes.
  int get tagLength;

  /// Seals [plaintext]; returns `ciphertext || tag`.
  Future<Uint8List> encrypt(Uint8List plaintext,
      {required Uint8List key, required Uint8List nonce, List<int> aad});

  /// Opens `ciphertext || tag`. Throws `AtDecryptionException` when
  /// authentication fails.
  Future<Uint8List> decrypt(Uint8List sealed,
      {required Uint8List key, required Uint8List nonce, List<int> aad});
}

/// AES-256-GCM (IANA HPKE AEAD id `0x0002`) behind the uniform face.
final class AesGcm256Aead implements AtAeadAlgorithm {
  const AesGcm256Aead();

  @override
  int get nonceLength => AesGcm256EncryptionAlgo.nonceLength;

  @override
  int get tagLength => AesGcm256EncryptionAlgo.tagLength;

  @override
  Future<Uint8List> encrypt(Uint8List plaintext,
          {required Uint8List key,
          required Uint8List nonce,
          List<int> aad = const []}) async =>
      AesGcm256EncryptionAlgo(_aesKey(key))
          .encrypt(plaintext, iv: InitialisationVector(nonce), aad: aad);

  @override
  Future<Uint8List> decrypt(Uint8List sealed,
          {required Uint8List key,
          required Uint8List nonce,
          List<int> aad = const []}) async =>
      AesGcm256EncryptionAlgo(_aesKey(key))
          .decrypt(sealed, iv: InitialisationVector(nonce), aad: aad);

  /// Wraps a raw 32-byte key as an [AESKey] (which carries it base64-encoded,
  /// per the at_chops contract).
  static AESKey _aesKey(Uint8List rawKey) => AESKey(base64Encode(rawKey));
}

/// ChaCha20-Poly1305 (IANA HPKE AEAD id `0x0003`) behind the uniform face.
final class ChaCha20Poly1305Aead implements AtAeadAlgorithm {
  const ChaCha20Poly1305Aead();

  @override
  int get nonceLength => ChaCha20Poly1305Algo.nonceLength;

  @override
  int get tagLength => ChaCha20Poly1305Algo.tagLength;

  @override
  Future<Uint8List> encrypt(Uint8List plaintext,
          {required Uint8List key,
          required Uint8List nonce,
          List<int> aad = const []}) =>
      const ChaCha20Poly1305Algo()
          .encrypt(plaintext, key: key, nonce: nonce, aad: aad);

  @override
  Future<Uint8List> decrypt(Uint8List sealed,
          {required Uint8List key,
          required Uint8List nonce,
          List<int> aad = const []}) =>
      const ChaCha20Poly1305Algo()
          .decrypt(sealed, key: key, nonce: nonce, aad: aad);
}
