import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_commons/at_commons.dart';
import 'package:ffi/ffi.dart';

/// AES-256-GCM authenticated encryption (AEAD), backed by OpenSSL 3 via
/// Dart FFI (`EVP_CIPHER_CTX` / `EVP_aes_256_gcm`).
///
/// Wire format, nonce handling, and AAD semantics are identical to
/// [AesGcm256EncryptionAlgo] (the pure-Dart counterpart) so the two
/// implementations are interoperable: data encrypted by one decrypts
/// correctly with the other.
///
/// The caller loads libcrypto (e.g. via [tryLoadLibCrypto]) and passes the
/// resulting [DynamicLibrary] via [AesGcm256FfiAlgo.fromLib].
/// Prefer [AtPqc.aesGcm256] for automatic FFI-vs-pure-Dart resolution.
final class AesGcm256FfiAlgo
    implements SymmetricEncryptionAlgorithm<Uint8List, Uint8List> {
  static const int nonceLength = 12;
  static const int tagLength = 16;

  final DynamicLibrary _lib;
  final AESKey _aesKey;

  late final EvpAes256GcmDart _evpAes256Gcm;
  late final EvpCipherCtxNewDart _ctxNew;
  late final EvpCipherCtxFreeDart _ctxFree;
  late final EvpEncryptInitExDart _encryptInitEx;
  late final EvpDecryptInitExDart _decryptInitEx;
  late final EvpEncryptUpdateDart _encryptUpdate;
  late final EvpDecryptUpdateDart _decryptUpdate;
  late final EvpEncryptFinalExDart _encryptFinalEx;
  late final EvpDecryptFinalExDart _decryptFinalEx;
  late final EvpCipherCtxCtrlDart _ctxCtrl;

  AesGcm256FfiAlgo.fromLib(this._lib, this._aesKey) {
    _evpAes256Gcm = _lib.lookupFunction<EvpAes256GcmNative, EvpAes256GcmDart>(
        'EVP_aes_256_gcm');
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
    _encryptFinalEx =
        _lib.lookupFunction<EvpEncryptFinalExNative, EvpEncryptFinalExDart>(
            'EVP_EncryptFinal_ex');
    _decryptFinalEx =
        _lib.lookupFunction<EvpDecryptFinalExNative, EvpDecryptFinalExDart>(
            'EVP_DecryptFinal_ex');
    _ctxCtrl =
        _lib.lookupFunction<EvpCipherCtxCtrlNative, EvpCipherCtxCtrlDart>(
            'EVP_CIPHER_CTX_ctrl');
  }

  @override
  Future<Uint8List> encrypt(Uint8List plainData,
      {InitialisationVector? iv, List<int> aad = const []}) async {
    final Uint8List keyBytes = _keyBytes();
    final List<int> nonce = _nonceBytes(iv);

    final Pointer<EVP_CIPHER_CTX> ctx = _ctxNew();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');

    try {
      final Pointer<EVP_CIPHER> cipher = _evpAes256Gcm();

      // 1. Init cipher without key/IV to set IV length first.
      if (_encryptInitEx(ctx, cipher, nullptr, nullptr, nullptr) <= 0) {
        throw StateError('EVP_EncryptInit_ex (cipher) failed');
      }

      // 2. Set IV length to 12 bytes.
      if (_ctxCtrl(ctx, evpCtrlGcmSetIvlen, nonceLength, nullptr) <= 0) {
        throw StateError('EVP_CIPHER_CTX_ctrl (set IV len) failed');
      }

      // 3. Set key and IV.
      final Pointer<Uint8> keyPtr = calloc<Uint8>(keyBytes.length);
      final Pointer<Uint8> ivPtr = calloc<Uint8>(nonce.length);
      keyPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);
      ivPtr.asTypedList(nonce.length).setAll(0, nonce);
      try {
        if (_encryptInitEx(ctx, nullptr, nullptr, keyPtr, ivPtr) <= 0) {
          throw StateError('EVP_EncryptInit_ex (key/IV) failed');
        }
      } finally {
        calloc.free(keyPtr);
        calloc.free(ivPtr);
      }

      // 4. Feed AAD (if any).
      if (aad.isNotEmpty) {
        final Pointer<Uint8> aadPtr = calloc<Uint8>(aad.length);
        aadPtr.asTypedList(aad.length).setAll(0, aad);
        final Pointer<Int32> aadOutLen = calloc<Int32>();
        try {
          if (_encryptUpdate(ctx, nullptr, aadOutLen, aadPtr, aad.length) <=
              0) {
            throw StateError('EVP_EncryptUpdate (AAD) failed');
          }
        } finally {
          calloc.free(aadPtr);
          calloc.free(aadOutLen);
        }
      }

      // 5. Encrypt plaintext.
      final Pointer<Uint8> plainBuf =
          calloc<Uint8>(plainData.isEmpty ? 1 : plainData.length);
      if (plainData.isNotEmpty) {
        plainBuf.asTypedList(plainData.length).setAll(0, plainData);
      }
      final Pointer<Uint8> outBuf =
          calloc<Uint8>(plainData.isEmpty ? 1 : plainData.length);
      final Pointer<Int32> outLen = calloc<Int32>();
      try {
        final int encLen;
        try {
          if (_encryptUpdate(ctx, outBuf, outLen, plainBuf, plainData.length) <=
              0) {
            throw StateError('EVP_EncryptUpdate (plaintext) failed');
          }
          encLen = outLen.value;
        } finally {
          calloc.free(plainBuf);
        }

        // 6. Finalise (GCM produces no extra output here, but required).
        final Pointer<Uint8> finalBuf = calloc<Uint8>(16);
        final Pointer<Int32> finalLen = calloc<Int32>();
        try {
          if (_encryptFinalEx(ctx, finalBuf, finalLen) <= 0) {
            throw StateError('EVP_EncryptFinal_ex failed');
          }

          // 7. Extract the 16-byte authentication tag.
          final Pointer<Uint8> tagBuf = calloc<Uint8>(tagLength);
          try {
            if (_ctxCtrl(ctx, evpCtrlGcmGetTag, tagLength, tagBuf.cast()) <=
                0) {
              throw StateError('EVP_CIPHER_CTX_ctrl (get tag) failed');
            }
            final Uint8List cipherText =
                Uint8List.fromList(outBuf.asTypedList(encLen));
            final Uint8List tag =
                Uint8List.fromList(tagBuf.asTypedList(tagLength));
            return Uint8List.fromList(cipherText + tag);
          } finally {
            calloc.free(tagBuf);
          }
        } finally {
          calloc.free(finalBuf);
          calloc.free(finalLen);
        }
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
      {InitialisationVector? iv, List<int> aad = const []}) async {
    if (encryptedData.length < tagLength) {
      throw AtDecryptionException(
          'AES-256-GCM (FFI) input shorter than the $tagLength-byte tag');
    }

    final Uint8List keyBytes = _keyBytes();
    final List<int> nonce = _nonceBytes(iv);
    final Uint8List cipherText =
        encryptedData.sublist(0, encryptedData.length - tagLength);
    final Uint8List tag =
        encryptedData.sublist(encryptedData.length - tagLength);

    final Pointer<EVP_CIPHER_CTX> ctx = _ctxNew();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');

    try {
      final Pointer<EVP_CIPHER> cipher = _evpAes256Gcm();

      // 1. Init cipher without key/IV.
      if (_decryptInitEx(ctx, cipher, nullptr, nullptr, nullptr) <= 0) {
        throw StateError('EVP_DecryptInit_ex (cipher) failed');
      }

      // 2. Set IV length.
      if (_ctxCtrl(ctx, evpCtrlGcmSetIvlen, nonceLength, nullptr) <= 0) {
        throw StateError('EVP_CIPHER_CTX_ctrl (set IV len) failed');
      }

      // 3. Set key and IV.
      final Pointer<Uint8> keyPtr = calloc<Uint8>(keyBytes.length);
      final Pointer<Uint8> ivPtr = calloc<Uint8>(nonce.length);
      keyPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);
      ivPtr.asTypedList(nonce.length).setAll(0, nonce);
      try {
        if (_decryptInitEx(ctx, nullptr, nullptr, keyPtr, ivPtr) <= 0) {
          throw StateError('EVP_DecryptInit_ex (key/IV) failed');
        }
      } finally {
        calloc.free(keyPtr);
        calloc.free(ivPtr);
      }

      // 4. Feed AAD (if any).
      if (aad.isNotEmpty) {
        final Pointer<Uint8> aadPtr = calloc<Uint8>(aad.length);
        aadPtr.asTypedList(aad.length).setAll(0, aad);
        final Pointer<Int32> aadOutLen = calloc<Int32>();
        try {
          if (_decryptUpdate(ctx, nullptr, aadOutLen, aadPtr, aad.length) <=
              0) {
            throw StateError('EVP_DecryptUpdate (AAD) failed');
          }
        } finally {
          calloc.free(aadPtr);
          calloc.free(aadOutLen);
        }
      }

      // 5. Decrypt ciphertext.
      final Pointer<Uint8> ctBuf =
          calloc<Uint8>(cipherText.isEmpty ? 1 : cipherText.length);
      if (cipherText.isNotEmpty) {
        ctBuf.asTypedList(cipherText.length).setAll(0, cipherText);
      }
      final Pointer<Uint8> outBuf =
          calloc<Uint8>(cipherText.isEmpty ? 1 : cipherText.length);
      final Pointer<Int32> outLen = calloc<Int32>();
      try {
        final int decLen;
        try {
          if (_decryptUpdate(ctx, outBuf, outLen, ctBuf, cipherText.length) <=
              0) {
            throw StateError('EVP_DecryptUpdate (ciphertext) failed');
          }
          decLen = outLen.value;
        } finally {
          calloc.free(ctBuf);
        }

        // 6. Set expected tag before finalise.
        final Pointer<Uint8> tagBuf = calloc<Uint8>(tagLength);
        tagBuf.asTypedList(tagLength).setAll(0, tag);
        try {
          if (_ctxCtrl(ctx, evpCtrlGcmSetTag, tagLength, tagBuf.cast()) <= 0) {
            throw StateError('EVP_CIPHER_CTX_ctrl (set tag) failed');
          }
        } finally {
          calloc.free(tagBuf);
        }

        // 7. Finalise — returns <= 0 on authentication failure.
        final Pointer<Uint8> finalBuf = calloc<Uint8>(16);
        final Pointer<Int32> finalLen = calloc<Int32>();
        try {
          final int ret = _decryptFinalEx(ctx, finalBuf, finalLen);
          if (ret <= 0) {
            throw AtDecryptionException(
                'AES-256-GCM (FFI) authentication failed: data was tampered '
                'with or the wrong key/nonce was used');
          }
          return Uint8List.fromList(outBuf.asTypedList(decLen));
        } finally {
          calloc.free(finalBuf);
          calloc.free(finalLen);
        }
      } finally {
        calloc.free(outBuf);
        calloc.free(outLen);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Uint8List _keyBytes() {
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
