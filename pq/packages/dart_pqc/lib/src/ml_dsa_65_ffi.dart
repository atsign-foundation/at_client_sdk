import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dart_pqc_base.dart';
import 'openssl_ffi_bindings.dart';

// ML-DSA-65 (FIPS 204) via OpenSSL 3 FFI — ported from demo 6's MlDsa65 class.
//
// Key sizes: pk=1952B  sk=4032B  sig≤3309B
// Algorithm name: "ML-DSA-65" (OpenSSL 3.3+)

/// ML-DSA-65 signing backed by OpenSSL 3 via Dart FFI.
///
/// Construct via [MlDsa65Ffi.fromLib].
final class MlDsa65Ffi implements MlDsa65Algorithm {
  static const int pkBytes = 1952;
  static const int skBytes = 4032;
  static const int maxSigBytes = 3309;

  // EVP_PKEY_CTX_new_from_name / free
  late final EvpPkeyCtxNewFromNameDart _ctxNewFromName;
  late final EvpPkeyCtxFreeDart _ctxFree;
  late final EvpPkeyFreeDart _pkeyFree;
  late final EvpPkeyKeygenInitDart _keygenInit;
  late final EvpPkeyKeygenDart _keygen;

  // EVP_MD_CTX_new / free
  late final EvpMdCtxNewDart _mdCtxNew;
  late final EvpMdCtxFreeDart _mdCtxFree;

  // EVP_DigestSignInit_ex / EVP_DigestVerifyInit_ex (7-arg, ML-DSA variant)
  late final EvpDigestSignInitExDart _digestSignInitEx;
  late final EvpDigestVerifyInitExDart _digestVerifyInitEx;

  // EVP_DigestSign / EVP_DigestVerify (one-shot)
  late final EvpDigestSignDart _digestSign;
  late final EvpDigestVerifyDart _digestVerify;

  // OSSL_PARAM_BLD — for raw key import
  late final OsslParamBldNewDart _bldNew;
  late final OsslParamBldFreeDart _bldFree;
  late final OsslParamBldToParamDart _bldToParam;
  late final OsslParamBldPushOctetStringDart _bldPushOctet;
  late final OsslParamFreeDart _paramFree;
  late final EvpPkeyFromdataInitDart _fromdataInit;
  late final EvpPkeyFromdataDart _fromdata;

  // EVP_PKEY_get_octet_string_param — raw key extraction
  late final EvpPkeyGetOctetStringParamDart _getOctetStringParam;

  MlDsa65Ffi.fromLib(DynamicLibrary lib) {
    _ctxNewFromName =
        lib.lookupFunction<EvpPkeyCtxNewFromNameNative, EvpPkeyCtxNewFromNameDart>(
            'EVP_PKEY_CTX_new_from_name');
    _ctxFree = lib.lookupFunction<EvpPkeyCtxFreeNative, EvpPkeyCtxFreeDart>(
        'EVP_PKEY_CTX_free');
    _pkeyFree = lib.lookupFunction<EvpPkeyFreeNative, EvpPkeyFreeDart>(
        'EVP_PKEY_free');
    _keygenInit =
        lib.lookupFunction<EvpPkeyKeygenInitNative, EvpPkeyKeygenInitDart>(
            'EVP_PKEY_keygen_init');
    _keygen = lib.lookupFunction<EvpPkeyKeygenNative, EvpPkeyKeygenDart>(
        'EVP_PKEY_keygen');
    _mdCtxNew =
        lib.lookupFunction<EvpMdCtxNewNative, EvpMdCtxNewDart>('EVP_MD_CTX_new');
    _mdCtxFree = lib
        .lookupFunction<EvpMdCtxFreeNative, EvpMdCtxFreeDart>('EVP_MD_CTX_free');
    _digestSignInitEx =
        lib.lookupFunction<EvpDigestSignInitExNative, EvpDigestSignInitExDart>(
            'EVP_DigestSignInit_ex');
    _digestVerifyInitEx =
        lib.lookupFunction<EvpDigestVerifyInitExNative, EvpDigestVerifyInitExDart>(
            'EVP_DigestVerifyInit_ex');
    _digestSign =
        lib.lookupFunction<EvpDigestSignNative, EvpDigestSignDart>('EVP_DigestSign');
    _digestVerify =
        lib.lookupFunction<EvpDigestVerifyNative, EvpDigestVerifyDart>(
            'EVP_DigestVerify');
    _bldNew = lib.lookupFunction<OsslParamBldNewNative, OsslParamBldNewDart>(
        'OSSL_PARAM_BLD_new');
    _bldFree = lib.lookupFunction<OsslParamBldFreeNative, OsslParamBldFreeDart>(
        'OSSL_PARAM_BLD_free');
    _bldToParam =
        lib.lookupFunction<OsslParamBldToParamNative, OsslParamBldToParamDart>(
            'OSSL_PARAM_BLD_to_param');
    _bldPushOctet =
        lib.lookupFunction<OsslParamBldPushOctetStringNative, OsslParamBldPushOctetStringDart>(
            'OSSL_PARAM_BLD_push_octet_string');
    _paramFree =
        lib.lookupFunction<OsslParamFreeNative, OsslParamFreeDart>('OSSL_PARAM_free');
    _fromdataInit =
        lib.lookupFunction<EvpPkeyFromdataInitNative, EvpPkeyFromdataInitDart>(
            'EVP_PKEY_fromdata_init');
    _fromdata = lib.lookupFunction<EvpPkeyFromdataNative, EvpPkeyFromdataDart>(
        'EVP_PKEY_fromdata');
    _getOctetStringParam =
        lib.lookupFunction<EvpPkeyGetOctetStringParamNative, EvpPkeyGetOctetStringParamDart>(
            'EVP_PKEY_get_octet_string_param');
  }

  // ── MlDsa65Algorithm ───────────────────────────────────────────────────────

  @override
  Future<PqcKeyPair> generateKeyPair() async {
    final algName = 'ML-DSA-65'.toNativeUtf8();
    final ctx = _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('ML-DSA-65: EVP_PKEY_CTX_new_from_name failed');
    try {
      if (_keygenInit(ctx) <= 0) throw StateError('ML-DSA-65: keygen_init failed');
      final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('ML-DSA-65: keygen failed');
        final pkey = pkeyPtr.value;
        try {
          final pk = _extractOctetParam(pkey, 'pub');
          final sk = _extractOctetParam(pkey, 'priv');
          return PqcKeyPair(publicKey: pk, secretKey: sk);
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

  @override
  Future<Uint8List> sign(Uint8List secretKey, Uint8List message) async {
    final Pointer<EVP_PKEY> pkey = _importKey(secretKey, 'priv', evpPkeyKeypair);
    try {
      final mdCtx = _mdCtxNew();
      if (mdCtx == nullptr) throw StateError('ML-DSA-65: EVP_MD_CTX_new failed');
      try {
        if (_digestSignInitEx(
                mdCtx, nullptr, nullptr, nullptr, nullptr, pkey, nullptr) <=
            0) {
          throw StateError('ML-DSA-65: EVP_DigestSignInit_ex failed');
        }
        final msgBuf = calloc<Uint8>(message.length);
        msgBuf.asTypedList(message.length).setAll(0, message);
        final sigLen = calloc<IntPtr>();
        try {
          if (_digestSign(mdCtx, nullptr, sigLen, msgBuf, message.length) <= 0) {
            throw StateError('ML-DSA-65: EVP_DigestSign (size query) failed');
          }
          final sigBuf = calloc<Uint8>(sigLen.value);
          try {
            if (_digestSign(mdCtx, sigBuf, sigLen, msgBuf, message.length) <= 0) {
              throw StateError('ML-DSA-65: EVP_DigestSign failed');
            }
            return Uint8List.fromList(sigBuf.asTypedList(sigLen.value));
          } finally {
            calloc.free(sigBuf);
          }
        } finally {
          calloc.free(sigLen);
          calloc.free(msgBuf);
        }
      } finally {
        _mdCtxFree(mdCtx);
      }
    } finally {
      _pkeyFree(pkey);
    }
  }

  @override
  Future<bool> verify(
      Uint8List publicKey, Uint8List message, Uint8List signature) async {
    final Pointer<EVP_PKEY> pkey = _importKey(publicKey, 'pub', evpPkeyPublicKey);
    try {
      final mdCtx = _mdCtxNew();
      if (mdCtx == nullptr) throw StateError('ML-DSA-65: EVP_MD_CTX_new failed');
      try {
        if (_digestVerifyInitEx(
                mdCtx, nullptr, nullptr, nullptr, nullptr, pkey, nullptr) <=
            0) {
          throw StateError('ML-DSA-65: EVP_DigestVerifyInit_ex failed');
        }
        final msgBuf = calloc<Uint8>(message.length);
        msgBuf.asTypedList(message.length).setAll(0, message);
        final sigBuf = calloc<Uint8>(signature.length);
        sigBuf.asTypedList(signature.length).setAll(0, signature);
        try {
          return _digestVerify(
                  mdCtx, sigBuf, signature.length, msgBuf, message.length) ==
              1;
        } finally {
          calloc.free(sigBuf);
          calloc.free(msgBuf);
        }
      } finally {
        _mdCtxFree(mdCtx);
      }
    } finally {
      _pkeyFree(pkey);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Uint8List _extractOctetParam(Pointer<EVP_PKEY> pkey, String paramName) {
    final name = paramName.toNativeUtf8();
    final outLen = calloc<IntPtr>();
    try {
      if (_getOctetStringParam(pkey, name, nullptr, 0, outLen) <= 0) {
        throw StateError('ML-DSA-65: get param "$paramName" size query failed');
      }
      final buf = calloc<Uint8>(outLen.value);
      try {
        if (_getOctetStringParam(pkey, name, buf, outLen.value, outLen) <= 0) {
          throw StateError('ML-DSA-65: get param "$paramName" failed');
        }
        return Uint8List.fromList(buf.asTypedList(outLen.value));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(outLen);
      calloc.free(name);
    }
  }

  Pointer<EVP_PKEY> _importKey(
      Uint8List keyBytes, String paramName, int selection) {
    final algName = 'ML-DSA-65'.toNativeUtf8();
    final pname = paramName.toNativeUtf8();
    final keyBuf = calloc<Uint8>(keyBytes.length);
    keyBuf.asTypedList(keyBytes.length).setAll(0, keyBytes);
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('ML-DSA-65: OSSL_PARAM_BLD_new failed');
      if (_bldPushOctet(bld, pname, keyBuf, keyBytes.length) <= 0) {
        _bldFree(bld);
        throw StateError('ML-DSA-65: bld push octet failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('ML-DSA-65: bld to param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('ML-DSA-65: ctx new from name failed');
      if (_fromdataInit(ctx) <= 0) throw StateError('ML-DSA-65: fromdata_init failed');
      if (_fromdata(ctx, pkeyPtr, selection, params) <= 0) {
        throw StateError('ML-DSA-65: fromdata failed');
      }
      return pkeyPtr.value;
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      calloc.free(keyBuf);
      calloc.free(pname);
      calloc.free(algName);
      calloc.free(pkeyPtr);
    }
  }
}
