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

  // Exactly one of these is set: the AESKey path decodes and validates
  // lazily at encrypt/decrypt time; the bytes path is validated and copied
  // at construction.
  final AESKey? _aesKey;
  final Uint8List? _keyBytes;

  AesGcm256EncryptionAlgo(AESKey aesKey)
      : _aesKey = aesKey,
        _keyBytes = null;

  /// Creates the algorithm from a raw 32-byte AES-256 key.
  ///
  /// The bytes are copied, so later changes to [keyBytes] do not affect this
  /// instance. For callers that hold the key as bytes rather than as an
  /// [AESKey]. Throws [AtEncryptionException] if [keyBytes] is not 32 bytes.
  ///
  /// The copy this instance keeps lives until [close] zeroes it. This
  /// constructor is for tests and the Dart VM. Browser production code keeps
  /// its keys in the WebCrypto sealer instead (D-29).
  AesGcm256EncryptionAlgo.fromKeyBytes(Uint8List keyBytes)
      : _aesKey = null,
        _keyBytes = _checkedCopy(keyBytes);

  /// Zeroes the key copy made by [AesGcm256EncryptionAlgo.fromKeyBytes]; the
  /// instance then refuses [encrypt] and [decrypt] with a [StateError]. A
  /// no-op for the [AESKey] constructor, whose key is decoded per call.
  void close() {
    final Uint8List? stored = _keyBytes;
    if (stored == null) return;
    stored.fillRange(0, stored.length, 0);
    _closed = true;
  }

  bool _closed = false;

  static Uint8List _checkedCopy(Uint8List keyBytes) {
    if (keyBytes.length != _keyLength) {
      throw AtEncryptionException(
          'AES-256-GCM requires a 256-bit key; got ${keyBytes.length * 8} bits');
    }
    return Uint8List.fromList(keyBytes);
  }

  static const int _keyLength = 32;

  @override
  Future<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv, List<int> aad = const []}) async {
    final crypto.SecretBox box = await _aesGcm.encrypt(
      plainData,
      secretKey: crypto.SecretKey(_keyBytesFor(encrypting: true)),
      nonce: _nonceBytesForEncrypt(iv),
      aad: aad,
    );
    return Uint8List.fromList(box.cipherText + box.mac.bytes);
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData,
      {InitialisationVector? iv, List<int> aad = const []}) async {
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
            nonce: _nonceBytesForDecrypt(iv), mac: crypto.Mac(tag)),
        secretKey: crypto.SecretKey(_keyBytesFor(encrypting: false)),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw AtDecryptionException(
          'AES-256-GCM authentication failed: data was tampered with or the '
          'wrong key/nonce was used');
    }
  }

  Uint8List _keyBytesFor({required bool encrypting}) {
    final Uint8List? stored = _keyBytes;
    if (stored != null) {
      if (_closed) throw StateError('AesGcm256EncryptionAlgo is closed');
      return stored;
    }
    // AESKey carries its material base64-encoded, per the at_chops contract.
    final Uint8List keyBytes = base64Decode(_aesKey!.key);
    if (keyBytes.length != _keyLength) {
      final String message =
          'AES-256-GCM requires a 256-bit key; got ${keyBytes.length * 8} bits';
      throw encrypting
          ? AtEncryptionException(message)
          : AtDecryptionException(message);
    }
    return keyBytes;
  }

  List<int> _nonceBytesForEncrypt(InitialisationVector? iv) {
    if (iv == null || iv.ivBytes.length != nonceLength) {
      throw AtEncryptionException(
          'AES-256-GCM requires an explicit $nonceLength-byte nonce; '
          'use AtChopsUtil.generateRandomIV($nonceLength)');
    }
    return iv.ivBytes;
  }

  List<int> _nonceBytesForDecrypt(InitialisationVector? iv) {
    if (iv == null || iv.ivBytes.length != nonceLength) {
      throw AtDecryptionException(
          'AES-256-GCM requires an explicit $nonceLength-byte nonce; '
          'use AtChopsUtil.generateRandomIV($nonceLength)');
    }
    return iv.ivBytes;
  }
}
