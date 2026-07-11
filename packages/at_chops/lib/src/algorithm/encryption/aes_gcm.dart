import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/encryption/gcm_nonce.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_commons/at_commons.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:meta/meta.dart';

/// AES-256-GCM authenticated encryption (AEAD), backed by pure-Dart
/// (`package:cryptography`).
///
/// Unlike [AESEncryptionAlgo] (AES-CTR, unauthenticated), GCM output is
/// authenticated: tampering with the nonce, ciphertext or tag makes
/// [decrypt] throw [AtDecryptionException] instead of returning garbage.
///
/// Wire format: `nonce(12) || ciphertext || tag(16)`. The nonce is generated
/// INSIDE [encrypt] from the platform CSPRNG ([Random.secure]) on every call
/// and prepended to the output, so ciphertexts are self-contained — there is
/// no separate IV to convey in metadata, and callers cannot supply one.
///
/// This is deliberate: GCM is catastrophically broken by (key, nonce) reuse
/// — it leaks the XOR of the plaintexts AND the GHASH authentication key,
/// enabling forgery of every message under that key. Because at_protocol
/// symmetric keys are reused across multiple encryptions between rotations,
/// nonce uniqueness must not depend on calling code doing the right thing.
/// Passing `iv:` to [encrypt] or [decrypt] therefore throws.
///
/// [encryptWithNonce]/[decryptWithNonce] exist for the only callers with a
/// legitimate need for an explicit nonce: HPKE-style constructions whose
/// AEAD key is single-use (`pqSeal`/`pqOpen`), and known-answer test
/// vectors. Their wire format carries no nonce (`ciphertext || tag(16)`).
///
/// An optional [aad] (associated data) may be supplied: it is authenticated
/// but NOT encrypted, and must be byte-identical at [encrypt] and [decrypt]
/// or authentication fails. It defaults to empty, so callers that don't use
/// AAD are unaffected.
final class AesGcm256EncryptionAlgo
    implements SymmetricEncryptionAlgorithm<Uint8List, Uint8List> {
  static const int nonceLength = 12;
  static const int tagLength = 16;

  static final crypto.AesGcm _aesGcm = crypto.AesGcm.with256bits();

  final AESKey _aesKey;

  AesGcm256EncryptionAlgo(this._aesKey);

  /// Encrypts [plainData] and returns `nonce(12) || ciphertext || tag(16)`.
  ///
  /// A fresh nonce is drawn from [Random.secure] on every call. [iv] must be
  /// null; supplying one throws [AtEncryptionException] — nonce generation
  /// is owned by this class so a (key, nonce) pair can never be reused.
  @override
  Future<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv, List<int> aad = const []}) async {
    if (iv != null) {
      throw AtEncryptionException(
          'AES-256-GCM generates its own nonce internally and prepends it to '
          'the ciphertext; do not supply an IV');
    }
    final Uint8List nonce = generateGcmNonce();
    final Uint8List body =
        await encryptWithNonce(plainData, nonce: nonce, aad: aad);
    return Uint8List.fromList(nonce + body);
  }

  /// Decrypts `nonce(12) || ciphertext || tag(16)` as produced by [encrypt].
  ///
  /// [iv] must be null; the nonce is read from the input itself.
  @override
  Future<Uint8List> decrypt(Uint8List encryptedData,
      {InitialisationVector? iv, List<int> aad = const []}) async {
    if (iv != null) {
      throw AtDecryptionException(
          'AES-256-GCM reads its nonce from the first $nonceLength bytes of '
          'the ciphertext; do not supply an IV');
    }
    if (encryptedData.length < nonceLength + tagLength) {
      throw AtDecryptionException(
          'AES-256-GCM input shorter than the $nonceLength-byte nonce plus '
          'the $tagLength-byte tag');
    }
    final Uint8List nonce = encryptedData.sublist(0, nonceLength);
    return decryptWithNonce(encryptedData.sublist(nonceLength),
        nonce: nonce, aad: aad);
  }

  /// Encrypts [plainData] under a caller-supplied [nonce], returning
  /// `ciphertext || tag(16)` (the nonce is NOT prepended).
  ///
  /// DANGER: encrypting twice under the same (key, nonce) destroys both
  /// confidentiality and authenticity for that key. Only call this when the
  /// key itself is single-use — an HPKE-style construction deriving a fresh
  /// key per message (`pqSeal`) — or when verifying known-answer vectors.
  /// Everything else must use [encrypt].
  @internal
  Future<Uint8List> encryptWithNonce(Uint8List plainData,
      {required Uint8List nonce, List<int> aad = const []}) async {
    if (nonce.length != nonceLength) {
      throw AtEncryptionException(
          'AES-256-GCM requires a $nonceLength-byte nonce; '
          'got ${nonce.length} bytes');
    }
    final crypto.SecretBox box = await _aesGcm.encrypt(
      plainData,
      secretKey: crypto.SecretKey(_keyBytesForEncrypt()),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList(box.cipherText + box.mac.bytes);
  }

  /// Decrypts `ciphertext || tag(16)` under a caller-supplied [nonce].
  ///
  /// Counterpart of [encryptWithNonce]; same restrictions apply.
  @internal
  Future<Uint8List> decryptWithNonce(Uint8List encryptedData,
      {required Uint8List nonce, List<int> aad = const []}) async {
    if (nonce.length != nonceLength) {
      throw AtDecryptionException(
          'AES-256-GCM requires a $nonceLength-byte nonce; '
          'got ${nonce.length} bytes');
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
        crypto.SecretBox(cipherText, nonce: nonce, mac: crypto.Mac(tag)),
        secretKey: crypto.SecretKey(_keyBytesForDecrypt()),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw AtDecryptionException(
          'AES-256-GCM authentication failed: data was tampered with or the '
          'wrong key/nonce was used');
    }
  }

  Uint8List _keyBytesForEncrypt() {
    // AESKey carries its material base64-encoded, per the at_chops contract.
    final Uint8List keyBytes = base64Decode(_aesKey.key);
    if (keyBytes.length != 32) {
      throw AtEncryptionException(
          'AES-256-GCM requires a 256-bit key; got ${keyBytes.length * 8} bits');
    }
    return keyBytes;
  }

  Uint8List _keyBytesForDecrypt() {
    final Uint8List keyBytes = base64Decode(_aesKey.key);
    if (keyBytes.length != 32) {
      throw AtDecryptionException(
          'AES-256-GCM requires a 256-bit key; got ${keyBytes.length * 8} bits');
    }
    return keyBytes;
  }
}
