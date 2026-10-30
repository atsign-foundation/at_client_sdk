import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart';
import 'package:at_chops/src/algorithm/spec/ml_dsa_65_spec.dart';
import 'package:at_chops/src/algorithm/spec/output_length.dart';
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
/// (e.g. loaded via `tryLoadLibCrypto`).
///
/// [fromLib] does not probe the library — pinning one that lacks ML-DSA-65
/// (OpenSSL < 3.5) fails lazily, as a [StateError] from the first
/// [generateKeyPair]/[signBytes]/[verifyBytes] call. Gate on
/// `libCryptoSupportsMlDsa65` if you pin the library yourself.
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
  late final OsslParamBldNewDart _bldNew;
  late final OsslParamBldFreeDart _bldFree;
  late final OsslParamBldToParamDart _bldToParam;
  late final OsslParamBldPushOctetStringDart _bldPushOctet;
  late final OsslParamFreeDart _paramFree;
  late final EvpPkeyFromdataInitDart _fromdataInit;
  late final EvpPkeyFromdataDart _fromdata;

  MlDsa65FfiAlgo.fromLib(this._lib) {
    _ctxNewFromName = _lib.lookupFunction<EvpPkeyCtxNewFromNameNative,
        EvpPkeyCtxNewFromNameDart>('EVP_PKEY_CTX_new_from_name');
    _ctxFree = _lib.lookupFunction<EvpPkeyCtxFreeNative, EvpPkeyCtxFreeDart>(
        'EVP_PKEY_CTX_free');
    _pkeyFree = _lib
        .lookupFunction<EvpPkeyFreeNative, EvpPkeyFreeDart>('EVP_PKEY_free');
    _keygenInit =
        _lib.lookupFunction<EvpPkeyKeygenInitNative, EvpPkeyKeygenInitDart>(
            'EVP_PKEY_keygen_init');
    _keygen = _lib.lookupFunction<EvpPkeyKeygenNative, EvpPkeyKeygenDart>(
        'EVP_PKEY_keygen');
    _getRawPublicKey =
        _lib.lookupFunction<EvpPkeyGetRawKeyNative, EvpPkeyGetRawKeyDart>(
            'EVP_PKEY_get_raw_public_key');
    _getRawPrivateKey =
        _lib.lookupFunction<EvpPkeyGetRawKeyNative, EvpPkeyGetRawKeyDart>(
            'EVP_PKEY_get_raw_private_key');
    _newRawPrivateKeyEx = _lib.lookupFunction<EvpPkeyNewRawPrivateKeyExNative,
        EvpPkeyNewRawPrivateKeyExDart>('EVP_PKEY_new_raw_private_key_ex');
    _newRawPublicKeyEx = _lib.lookupFunction<EvpPkeyNewRawPublicKeyExNative,
        EvpPkeyNewRawPublicKeyExDart>('EVP_PKEY_new_raw_public_key_ex');
    _mdCtxNew = _lib
        .lookupFunction<EvpMdCtxNewNative, EvpMdCtxNewDart>('EVP_MD_CTX_new');
    _mdCtxFree = _lib.lookupFunction<EvpMdCtxFreeNative, EvpMdCtxFreeDart>(
        'EVP_MD_CTX_free');
    _digestSignInit =
        _lib.lookupFunction<EvpDigestSignInitNative, EvpDigestSignInitDart>(
            'EVP_DigestSignInit');
    _digestSign = _lib.lookupFunction<EvpDigestSignNative, EvpDigestSignDart>(
        'EVP_DigestSign');
    _digestVerifyInit =
        _lib.lookupFunction<EvpDigestVerifyInitNative, EvpDigestVerifyInitDart>(
            'EVP_DigestVerifyInit');
    _digestVerify =
        _lib.lookupFunction<EvpDigestVerifyNative, EvpDigestVerifyDart>(
            'EVP_DigestVerify');
    _bldNew = _lib.lookupFunction<OsslParamBldNewNative, OsslParamBldNewDart>(
        'OSSL_PARAM_BLD_new');
    _bldFree =
        _lib.lookupFunction<OsslParamBldFreeNative, OsslParamBldFreeDart>(
            'OSSL_PARAM_BLD_free');
    _bldToParam =
        _lib.lookupFunction<OsslParamBldToParamNative, OsslParamBldToParamDart>(
            'OSSL_PARAM_BLD_to_param');
    _bldPushOctet = _lib.lookupFunction<OsslParamBldPushOctetStringNative,
        OsslParamBldPushOctetStringDart>('OSSL_PARAM_BLD_push_octet_string');
    _paramFree = _lib.lookupFunction<OsslParamFreeNative, OsslParamFreeDart>(
        'OSSL_PARAM_free');
    _fromdataInit =
        _lib.lookupFunction<EvpPkeyFromdataInitNative, EvpPkeyFromdataInitDart>(
            'EVP_PKEY_fromdata_init');
    _fromdata = _lib.lookupFunction<EvpPkeyFromdataNative, EvpPkeyFromdataDart>(
        'EVP_PKEY_fromdata');
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
        return _takeRawKeyPair(pkeyPtr.value, operation: 'EVP_PKEY_keygen');
      } finally {
        calloc.free(pkeyPtr);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  /// Deterministically derive the ML-DSA-65 key pair for [seed], the 32-byte
  /// FIPS 204 `ξ`, via `EVP_PKEY_fromdata` with OpenSSL's `seed` parameter.
  ///
  /// Returns `(publicKey: 1952 raw bytes, secretKey: 4032 raw bytes)`, the
  /// same bytes [MlDsa65PureDartAlgo.keyPairFromSeed] returns for [seed].
  ///
  /// Throws [ArgumentError] unless [seed] is [MlDsa65Sizes.seedBytes] long.
  Future<({Uint8List publicKey, Uint8List secretKey})> keyPairFromSeed(
      Uint8List seed) async {
    MlDsa65Sizes.validateSeed(seed);
    final Pointer<Utf8> algName = 'ML-DSA-65'.toNativeUtf8();
    final Pointer<Utf8> paramName = 'seed'.toNativeUtf8();
    final Pointer<Uint8> seedBuf = calloc<Uint8>(seed.length);
    seedBuf.asTypedList(seed.length).setAll(0, seed);

    final Pointer<Pointer<EVP_PKEY>> pkeyPtr = calloc<Pointer<EVP_PKEY>>();
    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    try {
      final Pointer<OSSL_PARAM_BLD> bld = _bldNew();
      if (bld == nullptr) throw StateError('OSSL_PARAM_BLD_new failed');
      if (_bldPushOctet(bld, paramName, seedBuf, seed.length) <= 0) {
        _bldFree(bld);
        throw StateError('OSSL_PARAM_BLD_push_octet_string failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('OSSL_PARAM_BLD_to_param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) {
        throw StateError('EVP_PKEY_CTX_new_from_name failed');
      }
      if (_fromdataInit(ctx) <= 0) {
        throw StateError('EVP_PKEY_fromdata_init failed');
      }
      if (_fromdata(ctx, pkeyPtr, evpPkeyKeypair, params) <= 0) {
        throw StateError('EVP_PKEY_fromdata (seed) failed');
      }
      return _takeRawKeyPair(pkeyPtr.value,
          operation: 'EVP_PKEY_fromdata (seed)');
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      seedBuf.asTypedList(seed.length).fillRange(0, seed.length, 0);
      calloc.free(seedBuf);
      calloc.free(paramName);
      calloc.free(algName);
      calloc.free(pkeyPtr);
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
    MlDsa65Sizes.validateSecretKey(secretKey);
    final Pointer<EVP_PKEY> pkey = _loadPrivateKey(secretKey);
    try {
      final Uint8List sig = _sign(pkey, message);
      checkOutputLength(sig.length, MlDsa65Sizes.signatureBytes,
          operation: 'EVP_DigestSign', label: 'signature');
      return sig;
    } finally {
      _pkeyFree(pkey);
    }
  }

  /// Verify [signature] over [message] against the raw 1952-byte [publicKey].
  ///
  /// Returns `false` for malformed or attacker-controlled input (wrong-length
  /// or garbage key/signature), matching the pure-Dart backend's contract —
  /// OpenSSL reports a signature mismatch as a return code, not an error.
  ///
  /// Throws [StateError] when OpenSSL itself cannot perform the operation —
  /// most commonly a libcrypto build without ML-DSA-65 (added to the default
  /// provider in OpenSSL 3.5). That is a misconfiguration, not a forged
  /// signature, and swallowing it as `false` would make the two
  /// indistinguishable. Gate on `libCryptoSupportsMlDsa65` before
  /// [MlDsa65FfiAlgo.fromLib], or use `AtPqc.mlDsa65`, which already does.
  @override
  Future<bool> verifyBytes(Uint8List message,
      {required Uint8List signature, required Uint8List publicKey}) async {
    if (!MlDsa65Sizes.hasValidVerifyLengths(publicKey, signature)) {
      return false;
    }
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

  /// Extracts and length-checks [pkey]'s raw key pair, then frees [pkey].
  ({Uint8List publicKey, Uint8List secretKey}) _takeRawKeyPair(
      Pointer<EVP_PKEY> pkey,
      {required String operation}) {
    try {
      final Uint8List pk = _extractRawPublicKey(pkey);
      final Uint8List sk = _extractRawPrivateKey(pkey);
      checkOutputLength(pk.length, MlDsa65Sizes.publicKeyBytes,
          operation: operation, label: 'public key');
      checkOutputLength(sk.length, MlDsa65Sizes.secretKeyBytes,
          operation: operation, label: 'secret key');
      return (publicKey: pk, secretKey: sk);
    } finally {
      _pkeyFree(pkey);
    }
  }

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
      if (pkey == nullptr) {
        throw StateError('EVP_PKEY_new_raw_private_key_ex failed');
      }
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
      if (pkey == nullptr) {
        throw StateError('EVP_PKEY_new_raw_public_key_ex failed');
      }
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

  bool _verify(Pointer<EVP_PKEY> pkey, Uint8List data, Uint8List signature) {
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
        // 1 = valid, 0 = signature mismatch, < 0 = the operation itself
        // failed. Only the middle case is a verification result; folding the
        // last one into `false` would make a backend failure indistinguishable
        // from a forged signature, which is what dropping verifyBytes'
        // catch-all set out to prevent.
        if (result < 0) throw StateError('EVP_DigestVerify failed');
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
