import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart';
import 'package:at_chops/src/algorithm/padding/pkcs7.dart';
import 'package:at_chops/src/algorithm/padding/types.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_commons/at_commons.dart';
import 'package:ffi/ffi.dart';

/// AES-CTR, backed by OpenSSL 3 via Dart FFI (`EVP_CIPHER_CTX` /
/// `EVP_aes_*_ctr`).
///
/// **CTR gives confidentiality only — it is not authenticated.** Ciphertext is
/// malleable and carries no tag; a caller needing integrity must add its own
/// MAC, or use [AesGcm256FfiAlgo] instead.
///
/// One deliberate divergence from the pure-Dart path: [AESEncryptionAlgo]
/// substitutes 16 zero bytes for a missing IV ("the bad old days"), and this
/// class rejects one. Pass an explicit IV and the two stay interchangeable.
///
/// Wire format, nonce handling, and padding semantics are identical to
/// [AESEncryptionAlgo] (the pure-Dart counterpart) so the two
/// implementations are interoperable: data encrypted by one decrypts
/// correctly with the other. Both use PKCS7 padding, despite CTR being a
/// stream cipher, to maintain backward compatibility.
///
/// The caller loads libcrypto (e.g. via [tryLoadLibCrypto]) and passes the
/// resulting [DynamicLibrary] via [AesCtrFfiAlgo.fromLib].
/// Prefer [AtPqc.aesCtr] for automatic FFI-vs-pure-Dart resolution.
class AesCtrFfiAlgo
    implements SymmetricEncryptionAlgorithm<Uint8List, Uint8List> {
  static const int ivLength = 16;

  final DynamicLibrary _lib;
  final AESKey _aesKey;
  PaddingAlgorithm? paddingAlgo;

  late final EvpAes128CtrDart _evpAes128Ctr;
  late final EvpAes192CtrDart _evpAes192Ctr;
  late final EvpAes256CtrDart _evpAes256Ctr;
  late final EvpCipherCtxNewDart _ctxNew;
  late final EvpCipherCtxFreeDart _ctxFree;
  late final EvpEncryptInitExDart _encryptInitEx;
  late final EvpDecryptInitExDart _decryptInitEx;
  late final EvpEncryptUpdateDart _encryptUpdate;
  late final EvpDecryptUpdateDart _decryptUpdate;

  AesCtrFfiAlgo.fromLib(this._lib, this._aesKey, {this.paddingAlgo}) {
    paddingAlgo ??= PKCS7Padding(PaddingParams()..blockSize = 16);

    _evpAes128Ctr = _lib.lookupFunction<EvpAes128CtrNative, EvpAes128CtrDart>(
        'EVP_aes_128_ctr');
    _evpAes192Ctr = _lib.lookupFunction<EvpAes192CtrNative, EvpAes192CtrDart>(
        'EVP_aes_192_ctr');
    _evpAes256Ctr = _lib.lookupFunction<EvpAes256CtrNative, EvpAes256CtrDart>(
        'EVP_aes_256_ctr');
    _ctxNew = _lib.lookupFunction<EvpCipherCtxNewNative, EvpCipherCtxNewDart>(
        'EVP_CIPHER_CTX_new');
    _ctxFree =
        _lib.lookupFunction<EvpCipherCtxFreeNative, EvpCipherCtxFreeDart>(
            'EVP_CIPHER_CTX_free');
    _encryptInitEx =
        _lib.lookupFunction<EvpEncryptInitExNative, EvpEncryptInitExDart>(
            'EVP_EncryptInit_ex');
    _decryptInitEx =
        _lib.lookupFunction<EvpDecryptInitExNative, EvpDecryptInitExDart>(
            'EVP_DecryptInit_ex');
    _encryptUpdate =
        _lib.lookupFunction<EvpEncryptUpdateNative, EvpEncryptUpdateDart>(
            'EVP_EncryptUpdate');
    _decryptUpdate =
        _lib.lookupFunction<EvpDecryptUpdateNative, EvpDecryptUpdateDart>(
            'EVP_DecryptUpdate');
    // `EVP_{En,De}cryptFinal_ex` are deliberately not bound: CTR reports a
    // block size of 1, so OpenSSL buffers nothing between calls and both
    // finalisers are unconditional no-ops returning 0 bytes.
  }

  Pointer<EVP_CIPHER> _getEvpCipher() {
    switch (_aesKey.getLength()) {
      case 16:
        return _evpAes128Ctr();
      case 24:
        return _evpAes192Ctr();
      case 32:
        return _evpAes256Ctr();
      default:
        throw AtEncryptionException(
            'Invalid AES key length. Valid lengths are 16/24/32 bytes');
    }
  }

  @override
  Future<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv}) async {
    final Uint8List keyBytes = _keyBytesForEncrypt();
    final List<int> nonce = _nonceBytesForEncrypt(iv);

    // Padding is required for AESEncryptionAlgo parity.
    final Uint8List paddedData =
        Uint8List.fromList(paddingAlgo!.addPadding(plainData));

    final Pointer<EVP_CIPHER_CTX> ctx = _ctxNew();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');

    try {
      final Pointer<EVP_CIPHER> cipher = _getEvpCipher();

      // 1. Init cipher, key and IV together. GCM splits this in two only to
      // fit an `EVP_CIPHER_CTX_ctrl` IV-length call between the halves; CTR's
      // IV length is fixed, so one call does it.
      final Pointer<Uint8> keyPtr = calloc<Uint8>(keyBytes.length);
      final Pointer<Uint8> ivPtr = calloc<Uint8>(nonce.length);
      keyPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);
      ivPtr.asTypedList(nonce.length).setAll(0, nonce);
      try {
        if (_encryptInitEx(ctx, cipher, nullptr, keyPtr, ivPtr) <= 0) {
          throw StateError('EVP_EncryptInit_ex (AES-CTR) failed');
        }
      } finally {
        keyPtr.asTypedList(keyBytes.length).fillRange(0, keyBytes.length, 0);
        calloc.free(keyPtr);
        calloc.free(ivPtr);
      }

      // 2. Encrypt the padded plaintext. Sized from the PADDED length — the
      // caller's plaintext length is never what crosses the boundary here.
      final int plainBufLen = paddedData.isEmpty ? 1 : paddedData.length;
      final Pointer<Uint8> plainBuf = calloc<Uint8>(plainBufLen);
      if (paddedData.isNotEmpty) {
        plainBuf.asTypedList(paddedData.length).setAll(0, paddedData);
      }
      final Pointer<Uint8> outBuf = calloc<Uint8>(plainBufLen);
      final Pointer<Int32> outLen = calloc<Int32>();
      try {
        final int encLen;
        try {
          if (_encryptUpdate(
                  ctx, outBuf, outLen, plainBuf, paddedData.length) <=
              0) {
            throw StateError('EVP_EncryptUpdate (plaintext) failed');
          }
          encLen = outLen.value;
        } finally {
          // Wipe the plaintext copy from native heap before freeing.
          plainBuf.asTypedList(plainBufLen).fillRange(0, plainBufLen, 0);
          calloc.free(plainBuf);
        }

        return Uint8List.fromList(outBuf.asTypedList(encLen));
      } finally {
        calloc.free(outBuf);
        calloc.free(outLen);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  @override
  Future<Uint8List> decrypt(Uint8List encryptedData,
      {InitialisationVector? iv}) async {
    final Uint8List keyBytes = _keyBytesForDecrypt();
    final List<int> nonce = _nonceBytesForDecrypt(iv);

    final Pointer<EVP_CIPHER_CTX> ctx = _ctxNew();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');

    try {
      final Pointer<EVP_CIPHER> cipher = _getEvpCipher();

      // 1. Init cipher, key and IV together — see the note in `encrypt`.
      final Pointer<Uint8> keyPtr = calloc<Uint8>(keyBytes.length);
      final Pointer<Uint8> ivPtr = calloc<Uint8>(nonce.length);
      keyPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);
      ivPtr.asTypedList(nonce.length).setAll(0, nonce);
      try {
        if (_decryptInitEx(ctx, cipher, nullptr, keyPtr, ivPtr) <= 0) {
          throw StateError('EVP_DecryptInit_ex (AES-CTR) failed');
        }
      } finally {
        keyPtr.asTypedList(keyBytes.length).fillRange(0, keyBytes.length, 0);
        calloc.free(keyPtr);
        calloc.free(ivPtr);
      }

      // 2. Decrypt, then strip the padding the pure-Dart path also applies.
      final int outBufLen = encryptedData.isEmpty ? 1 : encryptedData.length;
      final Pointer<Uint8> ctBuf = calloc<Uint8>(outBufLen);
      if (encryptedData.isNotEmpty) {
        ctBuf.asTypedList(encryptedData.length).setAll(0, encryptedData);
      }
      final Pointer<Uint8> outBuf = calloc<Uint8>(outBufLen);
      final Pointer<Int32> outLen = calloc<Int32>();
      try {
        final int decLen;
        try {
          if (_decryptUpdate(
                  ctx, outBuf, outLen, ctBuf, encryptedData.length) <=
              0) {
            throw StateError('EVP_DecryptUpdate (ciphertext) failed');
          }
          decLen = outLen.value;
        } finally {
          calloc.free(ctBuf);
        }

        final Uint8List decryptedBytesWithPadding =
            Uint8List.fromList(outBuf.asTypedList(decLen));
        return Uint8List.fromList(
            paddingAlgo!.removePadding(decryptedBytesWithPadding));
      } finally {
        // Wipe the recovered plaintext from native heap before freeing.
        outBuf.asTypedList(outBufLen).fillRange(0, outBufLen, 0);
        calloc.free(outBuf);
        calloc.free(outLen);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Uint8List _keyBytesForEncrypt() {
    final Uint8List keyBytes = base64Decode(_aesKey.key);
    final int len = keyBytes.length;
    if (len != 16 && len != 24 && len != 32) {
      throw AtEncryptionException(
          'Invalid AES key length. Valid lengths are 16/24/32 bytes');
    }
    return keyBytes;
  }

  Uint8List _keyBytesForDecrypt() {
    final Uint8List keyBytes = base64Decode(_aesKey.key);
    final int len = keyBytes.length;
    if (len != 16 && len != 24 && len != 32) {
      throw AtDecryptionException(
          'Invalid AES key length. Valid lengths are 16/24/32 bytes');
    }
    return keyBytes;
  }

  List<int> _nonceBytesForEncrypt(InitialisationVector? iv) {
    if (iv == null || iv.ivBytes.length != ivLength) {
      throw AtEncryptionException(
          'AES-CTR requires an explicit $ivLength-byte nonce; '
          'use AtChopsUtil.generateRandomIV($ivLength)');
    }
    return iv.ivBytes;
  }

  List<int> _nonceBytesForDecrypt(InitialisationVector? iv) {
    if (iv == null || iv.ivBytes.length != ivLength) {
      throw AtDecryptionException(
          'AES-CTR requires an explicit $ivLength-byte nonce; '
          'use AtChopsUtil.generateRandomIV($ivLength)');
    }
    return iv.ivBytes;
  }
}
