import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:cryptography/cryptography.dart' as crypto;

/// ChaCha20-Poly1305 AEAD (RFC 8439), keyed and nonced per call.
///
/// Exists for RFC 9180 HPKE at AEAD id `0x0003`, which is the only AEAD the
/// IETF HPKE working group publishes vectors for at KEM `0x647A`. Choosing
/// AES-256-GCM there would mean shipping a suite with no published end-to-end
/// vector.
///
/// Wire format matches [AesGcm256EncryptionAlgo]'s: `ciphertext || tag(16)`,
/// with the nonce carried outside rather than prepended, because HPKE derives
/// the nonce rather than transmitting it.
final class ChaCha20Poly1305Algo {
  static const int keyLength = 32;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  static final crypto.Chacha20 _algo = crypto.Chacha20.poly1305Aead();

  const ChaCha20Poly1305Algo();

  /// Seals [plaintext] under [key] and [nonce], returning
  /// `ciphertext || tag`.
  Future<Uint8List> encrypt(
    Uint8List plaintext, {
    required Uint8List key,
    required Uint8List nonce,
    List<int> aad = const [],
  }) async {
    _check(key, nonce);
    final box = await _algo.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList(box.cipherText + box.mac.bytes);
  }

  /// Opens `ciphertext || tag` under [key] and [nonce].
  ///
  /// Throws [AtDecryptionException] on any authentication failure — a wrong
  /// key, a tampered ciphertext and a mismatched [aad] are indistinguishable,
  /// which is the intended AEAD contract rather than an omission.
  Future<Uint8List> decrypt(
    Uint8List sealed, {
    required Uint8List key,
    required Uint8List nonce,
    List<int> aad = const [],
  }) async {
    _check(key, nonce);
    if (sealed.length < tagLength) {
      throw AtDecryptionException(
          'ChaCha20-Poly1305 input shorter than the $tagLength-byte tag');
    }
    final cipherText = sealed.sublist(0, sealed.length - tagLength);
    final tag = sealed.sublist(sealed.length - tagLength);
    try {
      final plain = await _algo.decrypt(
        crypto.SecretBox(cipherText, nonce: nonce, mac: crypto.Mac(tag)),
        secretKey: crypto.SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw AtDecryptionException(
          'ChaCha20-Poly1305 authentication failed: data was tampered with, '
          'or the wrong key, nonce or associated data was used');
    }
  }

  void _check(Uint8List key, Uint8List nonce) {
    // Checked rather than trusted: a short key or nonce reaching the cipher
    // produces an opaque failure well away from the caller that supplied it.
    if (key.length != keyLength) {
      throw ArgumentError.value(
          key.length, 'key', 'ChaCha20-Poly1305 key must be $keyLength bytes');
    }
    if (nonce.length != nonceLength) {
      throw ArgumentError.value(nonce.length, 'nonce',
          'ChaCha20-Poly1305 nonce must be $nonceLength bytes');
    }
  }
}
