import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart';
import 'package:at_commons/at_commons.dart';
import 'package:ffi/ffi.dart';

/// ML-DSA-65 (FIPS 204) digital signature backed by OpenSSL 3 via Dart FFI.
///
/// Unlike [MlKem768FfiAlgo], secret keys are real serializable byte arrays —
/// `EVP_PKEY_get_raw_private_key` returns the full 4032-byte secret key for
/// ML-DSA-65. Both public (1952 bytes) and secret (4032 bytes) keys can be
/// persisted and round-tripped between backends.
///
/// Implements [AtSignatureAlgorithm] — call [generateKeyPair], [signBytes],
/// and [verifyBytes] directly.
///
/// The stateful [AtSigningAlgorithm] path ([secretKey]/[sign]/[verify]) is
/// retained for compatibility with the published 3.3.0 surface; it is
/// deprecated — new code should pass key material per call.
///
/// Prefer [AtPqc.mlDsa65], which auto-resolves to this backend when libcrypto
/// supports ML-DSA-65 and falls back to pure-Dart otherwise. Construct via
/// [MlDsa65FfiAlgo.fromLib] only to pin a specific [DynamicLibrary]
/// (e.g. loaded via [tryLoadLibCrypto]).
final class MlDsa65FfiAlgo implements AtSigningAlgorithm, AtSignatureAlgorithm {
  final DynamicLibrary _lib;

  Uint8List? _secretKey;

  @Deprecated('Pass the secret key to signBytes instead.')
  set secretKey(Uint8List value) => _secretKey = value;

  late final EvpPkeyCtxNewFromNameDart _ctxNewFromName;
  late final EvpPkeyCtxFreeDart _ctxFree;
  late final EvpPkeyFreeDart _pkeyFree;
  late final EvpPkeyKeygenInitDart _keygenInit;
  late final EvpPkeyKeygenDart _keygen;
  late final EvpPkeyGetRawKeyDart _getRawPublicKey;
  late final EvpPkeyGetRawKeyDart _getRawPrivateKey;
  late final EvpPkeyNewRawPrivateKeyExDart _newRawPrivateKeyEx;
  late final EvpPkeyNewRawPublicKeyExDart _newRawPublicKeyEx;
  late final EvpMdCtxNewDart _mdCtxNew;
  late final EvpMdCtxFreeDart _mdCtxFree;
  late final EvpDigestSignInitDart _digestSignInit;
  late final EvpDigestSignDart _digestSign;
  late final EvpDigestVerifyInitDart _digestVerifyInit;
  late final EvpDigestVerifyDart _digestVerify;

  MlDsa65FfiAlgo.fromLib(this._lib) {
    _ctxNewFromName = _lib.lookupFunction<EvpPkeyCtxNewFromNameNative,
        EvpPkeyCtxNewFromNameDart>('EVP_PKEY_CTX_new_from_name');
    _ctxFree = _lib.lookupFunction<EvpPkeyCtxFreeNative, EvpPkeyCtxFreeDart>(
        'EVP_PKEY_CTX_free');
    _pkeyFree = _lib.lookupFunction<EvpPkeyFreeNative, EvpPkeyFreeDart>(
        'EVP_PKEY_free');
    _keygenInit = _lib.lookupFunction<EvpPkeyKeygenInitNative,
        EvpPkeyKeygenInitDart>('EVP_PKEY_keygen_init');
    _keygen = _lib.lookupFunction<EvpPkeyKeygenNative, EvpPkeyKeygenDart>(
        'EVP_PKEY_keygen');
    _getRawPublicKey = _lib.lookupFunction<EvpPkeyGetRawKeyNative,
        EvpPkeyGetRawKeyDart>('EVP_PKEY_get_raw_public_key');
    _getRawPrivateKey = _lib.lookupFunction<EvpPkeyGetRawKeyNative,
        EvpPkeyGetRawKeyDart>('EVP_PKEY_get_raw_private_key');
    _newRawPrivateKeyEx = _lib.lookupFunction<EvpPkeyNewRawPrivateKeyExNative,
        EvpPkeyNewRawPrivateKeyExDart>('EVP_PKEY_new_raw_private_key_ex');
    _newRawPublicKeyEx = _lib.lookupFunction<EvpPkeyNewRawPublicKeyExNative,
        EvpPkeyNewRawPublicKeyExDart>('EVP_PKEY_new_raw_public_key_ex');
    _mdCtxNew = _lib.lookupFunction<EvpMdCtxNewNative, EvpMdCtxNewDart>(
        'EVP_MD_CTX_new');
    _mdCtxFree = _lib.lookupFunction<EvpMdCtxFreeNative, EvpMdCtxFreeDart>(
        'EVP_MD_CTX_free');
    _digestSignInit = _lib.lookupFunction<EvpDigestSignInitNative,
        EvpDigestSignInitDart>('EVP_DigestSignInit');
    _digestSign = _lib.lookupFunction<EvpDigestSignNative, EvpDigestSignDart>(
        'EVP_DigestSign');
    _digestVerifyInit = _lib.lookupFunction<EvpDigestVerifyInitNative,
        EvpDigestVerifyInitDart>('EVP_DigestVerifyInit');
    _digestVerify = _lib
        .lookupFunction<EvpDigestVerifyNative, EvpDigestVerifyDart>(
            'EVP_DigestVerify');
  }

  /// Generate a fresh ML-DSA-65 key pair via OpenSSL.
  ///
  /// Returns `(publicKey: 1952 raw bytes, secretKey: 4032 raw bytes)`.
  /// Both values are serializable and interoperable with [MlDsa65PureDartAlgo].
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair() async {
    final Pointer<Utf8> algName = 'ML-DSA-65'.toNativeUtf8();
    final Pointer<EVP_PKEY_CTX> ctx =
        _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new_from_name failed');

    try {
      if (_keygenInit(ctx) <= 0) {
        throw StateError('EVP_PKEY_keygen_init failed');
      }
      final Pointer<Pointer<EVP_PKEY>> pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) {
          throw StateError('EVP_PKEY_keygen failed');
        }
        final Pointer<EVP_PKEY> pkey = pkeyPtr.value;
        try {
          return (
            publicKey: _extractRawPublicKey(pkey),
            secretKey: _extractRawPrivateKey(pkey),
          );
        } finally {
          _pkeyFree(pkey);
        }
      } finally {
        calloc.free(pkeyPtr);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  // ── AtSignatureAlgorithm ────────────────────────────────────────────────

  /// Sign [message] with the raw 4032-byte [secretKey].
  ///
  /// Returns a 3309-byte signature. Signing uses OpenSSL's internal
  /// randomness, so signatures are non-deterministic.
  @override
  Future<Uint8List> signBytes(Uint8List message,
      {required Uint8List secretKey}) async {
    final Pointer<EVP_PKEY> pkey = _loadPrivateKey(secretKey);
    try {
      return _sign(pkey, message);
    } finally {
      _pkeyFree(pkey);
    }
  }

  /// Verify [signature] over [message] against the raw 1952-byte [publicKey].
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    final Pointer<EVP_PKEY> pkey = _loadPublicKey(publicKey);
    try {
      return _verify(pkey, message, signature);
    } finally {
      _pkeyFree(pkey);
    }
  }

  // ── AtSigningAlgorithm (deprecated stateful path) ───────────────────────────

  @Deprecated('Use signBytes with explicit key material instead.')
  @override
  Future<Uint8List> sign(Uint8List data) async {
    if (_secretKey == null) {
      throw AtSigningException(
          'ML-DSA-65 secret key must be set before signing');
    }
    return signBytes(data, secretKey: _secretKey!);
  }

  @Deprecated('Use verifyBytes with explicit key material instead.')
  @override
  Future<bool> verify(Uint8List signedData, Uint8List signature,
      {String? publicKey}) async {
    if (publicKey == null) {
      throw AtSigningException(
          'public key must be provided for ML-DSA-65 signature verification');
    }
    final Uint8List pkBytes = base64Decode(publicKey);
    return verifyBytes(signedData, signature: signature, publicKey: pkBytes);
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  Uint8List _extractRawPublicKey(Pointer<EVP_PKEY> pkey) {
    final Pointer<IntPtr> lenPtr = calloc<IntPtr>();
    try {
      if (_getRawPublicKey(pkey, nullptr, lenPtr) <= 0) {
        throw StateError('EVP_PKEY_get_raw_public_key (size) failed');
      }
      final Pointer<Uint8> buf = calloc<Uint8>(lenPtr.value);
      try {
        if (_getRawPublicKey(pkey, buf, lenPtr) <= 0) {
          throw StateError('EVP_PKEY_get_raw_public_key failed');
        }
        return Uint8List.fromList(buf.asTypedList(lenPtr.value));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(lenPtr);
    }
  }

  Uint8List _extractRawPrivateKey(Pointer<EVP_PKEY> pkey) {
    final Pointer<IntPtr> lenPtr = calloc<IntPtr>();
    try {
      if (_getRawPrivateKey(pkey, nullptr, lenPtr) <= 0) {
        throw StateError('EVP_PKEY_get_raw_private_key (size) failed');
      }
      final Pointer<Uint8> buf = calloc<Uint8>(lenPtr.value);
      try {
        if (_getRawPrivateKey(pkey, buf, lenPtr) <= 0) {
          throw StateError('EVP_PKEY_get_raw_private_key failed');
        }
        return Uint8List.fromList(buf.asTypedList(lenPtr.value));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(lenPtr);
    }
  }

  Pointer<EVP_PKEY> _loadPrivateKey(Uint8List keyBytes) {
    final Pointer<Utf8> algName = 'ML-DSA-65'.toNativeUtf8();
    final Pointer<Uint8> buf = calloc<Uint8>(keyBytes.length);
    buf.asTypedList(keyBytes.length).setAll(0, keyBytes);
    try {
      final Pointer<EVP_PKEY> pkey =
          _newRawPrivateKeyEx(nullptr, algName, nullptr, buf, keyBytes.length);
      if (pkey == nullptr) throw StateError('EVP_PKEY_new_raw_private_key_ex failed');
      return pkey;
    } finally {
      calloc.free(buf);
      calloc.free(algName);
    }
  }

  Pointer<EVP_PKEY> _loadPublicKey(Uint8List keyBytes) {
    final Pointer<Utf8> algName = 'ML-DSA-65'.toNativeUtf8();
    final Pointer<Uint8> buf = calloc<Uint8>(keyBytes.length);
    buf.asTypedList(keyBytes.length).setAll(0, keyBytes);
    try {
      final Pointer<EVP_PKEY> pkey =
          _newRawPublicKeyEx(nullptr, algName, nullptr, buf, keyBytes.length);
      if (pkey == nullptr) throw StateError('EVP_PKEY_new_raw_public_key_ex failed');
      return pkey;
    } finally {
      calloc.free(buf);
      calloc.free(algName);
    }
  }

  Uint8List _sign(Pointer<EVP_PKEY> pkey, Uint8List data) {
    final Pointer<EVP_MD_CTX> ctx = _mdCtxNew();
    if (ctx == nullptr) throw StateError('EVP_MD_CTX_new failed');
    try {
      if (_digestSignInit(ctx, nullptr, nullptr, nullptr, pkey) <= 0) {
        throw StateError('EVP_DigestSignInit failed');
      }

      final Pointer<Uint8> dataBuf = calloc<Uint8>(data.length);
      dataBuf.asTypedList(data.length).setAll(0, data);
      final Pointer<IntPtr> sigLen = calloc<IntPtr>();
      try {
        if (_digestSign(ctx, nullptr, sigLen, dataBuf, data.length) <= 0) {
          throw StateError('EVP_DigestSign size query failed');
        }
        final Pointer<Uint8> sigBuf = calloc<Uint8>(sigLen.value);
        try {
          if (_digestSign(ctx, sigBuf, sigLen, dataBuf, data.length) <= 0) {
            throw StateError('EVP_DigestSign failed');
          }
          return Uint8List.fromList(sigBuf.asTypedList(sigLen.value));
        } finally {
          calloc.free(sigBuf);
        }
      } finally {
        calloc.free(dataBuf);
        calloc.free(sigLen);
      }
    } finally {
      _mdCtxFree(ctx);
    }
  }

  bool _verify(
      Pointer<EVP_PKEY> pkey, Uint8List data, Uint8List signature) {
    final Pointer<EVP_MD_CTX> ctx = _mdCtxNew();
    if (ctx == nullptr) throw StateError('EVP_MD_CTX_new failed');
    try {
      if (_digestVerifyInit(ctx, nullptr, nullptr, nullptr, pkey) <= 0) {
        throw StateError('EVP_DigestVerifyInit failed');
      }

      final Pointer<Uint8> dataBuf = calloc<Uint8>(data.length);
      dataBuf.asTypedList(data.length).setAll(0, data);
      final Pointer<Uint8> sigBuf = calloc<Uint8>(signature.length);
      sigBuf.asTypedList(signature.length).setAll(0, signature);
      try {
        final int result =
            _digestVerify(ctx, sigBuf, signature.length, dataBuf, data.length);
        return result == 1;
      } finally {
        calloc.free(dataBuf);
        calloc.free(sigBuf);
      }
    } finally {
      _mdCtxFree(ctx);
    }
  }
}
