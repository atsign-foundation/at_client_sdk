import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/src/at_algorithm.dart';
import 'package:at_chops/src/ffi/openssl_ffi_bindings.dart';
import 'package:ffi/ffi.dart';

/// ML-KEM-768 (FIPS 203) KEM backed by OpenSSL 3 via Dart FFI.
///
/// **Secret-key constraint:** OpenSSL's EVP API does not expose raw ML-KEM-768
/// secret-key bytes. [generateKeyPair] therefore stores the live `EVP_PKEY*`
/// in an internal registry and returns an 8-byte opaque handle as `secretKey`.
/// The handle is valid only within the same process lifetime and is **not
/// serializable** — persisted ML-KEM secret keys (e.g. loaded from a
/// `.atKeys` file) must be used with [MlKem768PureDartAlgo] instead.
///
/// Call [releaseKeyPair] when a key pair is no longer needed to free the
/// underlying native memory.
///
/// The caller loads libcrypto (e.g. via [tryLoadLibCrypto]) and passes the
/// resulting [DynamicLibrary] in via [MlKem768FfiAlgo.fromLib]. [AtPqc]
/// intentionally does not auto-resolve standalone ML-KEM-768: this backend's
/// secret keys are process-lifetime handles (see above), which is unsafe
/// behind a generic facade whose pure-Dart branch returns serializable keys.
final class MlKem768FfiAlgo implements AtKemAlgorithm {
  final DynamicLibrary _lib;
  final Random _rng = Random.secure();

  // Registry of live EVP_PKEY* objects, keyed by a random 64-bit handle.
  final Map<int, Pointer<EVP_PKEY>> _keys = {};

  late final EvpPkeyCtxNewFromNameDart _ctxNewFromName;
  late final EvpPkeyCtxNewDart _ctxNew;
  late final EvpPkeyCtxFreeDart _ctxFree;
  late final EvpPkeyFreeDart _pkeyFree;
  late final EvpPkeyKeygenInitDart _keygenInit;
  late final EvpPkeyKeygenDart _keygen;
  late final EvpPkeyGet1EncodedPublicKeyDart _get1EncodedPubKey;
  late final EvpPkeyKemInitDart _encapsInit;
  late final EvpPkeyEncapsulateDart _encapsulate;
  late final EvpPkeyKemInitDart _decapsInit;
  late final EvpPkeyDecapsulateDart _decapsulate;
  late final OsslParamBldNewDart _bldNew;
  late final OsslParamBldFreeDart _bldFree;
  late final OsslParamBldToParamDart _bldToParam;
  late final OsslParamBldPushOctetStringDart _bldPushOctet;
  late final OsslParamFreeDart _paramFree;
  late final EvpPkeyFromdataInitDart _fromdataInit;
  late final EvpPkeyFromdataDart _fromdata;
  late final CryptoFreeDart _cryptoFree;

  MlKem768FfiAlgo.fromLib(this._lib) {
    _ctxNewFromName = _lib.lookupFunction<EvpPkeyCtxNewFromNameNative,
        EvpPkeyCtxNewFromNameDart>('EVP_PKEY_CTX_new_from_name');
    _ctxNew = _lib.lookupFunction<EvpPkeyCtxNewNative, EvpPkeyCtxNewDart>(
        'EVP_PKEY_CTX_new');
    _ctxFree = _lib.lookupFunction<EvpPkeyCtxFreeNative, EvpPkeyCtxFreeDart>(
        'EVP_PKEY_CTX_free');
    _pkeyFree = _lib
        .lookupFunction<EvpPkeyFreeNative, EvpPkeyFreeDart>('EVP_PKEY_free');
    _keygenInit =
        _lib.lookupFunction<EvpPkeyKeygenInitNative, EvpPkeyKeygenInitDart>(
            'EVP_PKEY_keygen_init');
    _keygen = _lib.lookupFunction<EvpPkeyKeygenNative, EvpPkeyKeygenDart>(
        'EVP_PKEY_keygen');
    _get1EncodedPubKey = _lib.lookupFunction<EvpPkeyGet1EncodedPublicKeyNative,
        EvpPkeyGet1EncodedPublicKeyDart>('EVP_PKEY_get1_encoded_public_key');
    _encapsInit = _lib.lookupFunction<EvpPkeyKemInitNative, EvpPkeyKemInitDart>(
        'EVP_PKEY_encapsulate_init');
    _encapsulate =
        _lib.lookupFunction<EvpPkeyEncapsulateNative, EvpPkeyEncapsulateDart>(
            'EVP_PKEY_encapsulate');
    _decapsInit = _lib.lookupFunction<EvpPkeyKemInitNative, EvpPkeyKemInitDart>(
        'EVP_PKEY_decapsulate_init');
    _decapsulate =
        _lib.lookupFunction<EvpPkeyDecapsulateNative, EvpPkeyDecapsulateDart>(
            'EVP_PKEY_decapsulate');
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
    _cryptoFree =
        _lib.lookupFunction<CryptoFreeNative, CryptoFreeDart>('CRYPTO_free');
  }

  /// Generate a fresh ML-KEM-768 key pair via OpenSSL.
  ///
  /// Returns `(publicKey: 1184 raw bytes, secretKey: 8-byte opaque handle)`.
  /// The handle is **not serializable** — see class docs. Pass a 64-byte FIPS
  /// 203 seed (`d || z`) for deterministic generation — used internally by
  /// the X-Wing FFI backend, whose ML-KEM secret key is derived
  /// deterministically from the X-Wing seed.
  @override
  Future<({Uint8List publicKey, Uint8List secretKey})> generateKeyPair(
      [Uint8List? seed]) async {
    if (seed != null) return _generateKeyPairFromSeed(seed);

    final Pointer<Utf8> algName = 'ML-KEM-768'.toNativeUtf8();
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
        final Uint8List pubKeyBytes = _extractPublicKeyBytes(pkey);
        final int handle = _registerKey(pkey);
        return (publicKey: pubKeyBytes, secretKey: _encodeHandle(handle));
      } finally {
        calloc.free(pkeyPtr);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  Future<({Uint8List publicKey, Uint8List secretKey})> _generateKeyPairFromSeed(
      Uint8List seed) async {
    if (seed.length != 64) {
      throw ArgumentError.value(
          seed.length, 'seed', 'ML-KEM-768 seed must be 64 bytes (d || z)');
    }
    final Pointer<Utf8> algName = 'ML-KEM-768'.toNativeUtf8();
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
      final Pointer<EVP_PKEY> pkey = pkeyPtr.value;
      final Uint8List pubKeyBytes = _extractPublicKeyBytes(pkey);
      final int handle = _registerKey(pkey);
      return (publicKey: pubKeyBytes, secretKey: _encodeHandle(handle));
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      calloc.free(seedBuf);
      calloc.free(paramName);
      calloc.free(algName);
      calloc.free(pkeyPtr);
    }
  }

  @override
  Future<({Uint8List ciphertext, Uint8List sharedSecret})> encapsulate(
      Uint8List publicKey) async {
    final Pointer<EVP_PKEY> pubKeyPtr = _importPublicKey(publicKey);
    try {
      final Pointer<EVP_PKEY_CTX> ctx = _ctxNew(pubKeyPtr, nullptr);
      if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new failed');
      try {
        if (_encapsInit(ctx, nullptr) <= 0) {
          throw StateError('EVP_PKEY_encapsulate_init failed');
        }

        final Pointer<IntPtr> ctLen = calloc<IntPtr>();
        final Pointer<IntPtr> ssLen = calloc<IntPtr>();
        try {
          if (_encapsulate(ctx, nullptr, ctLen, nullptr, ssLen) <= 0) {
            throw StateError('EVP_PKEY_encapsulate size query failed');
          }
          final Pointer<Uint8> ctBuf = calloc<Uint8>(ctLen.value);
          final Pointer<Uint8> ssBuf = calloc<Uint8>(ssLen.value);
          try {
            if (_encapsulate(ctx, ctBuf, ctLen, ssBuf, ssLen) <= 0) {
              throw StateError('EVP_PKEY_encapsulate failed');
            }
            return (
              ciphertext: Uint8List.fromList(ctBuf.asTypedList(ctLen.value)),
              sharedSecret: Uint8List.fromList(ssBuf.asTypedList(ssLen.value)),
            );
          } finally {
            calloc.free(ctBuf);
            calloc.free(ssBuf);
          }
        } finally {
          calloc.free(ctLen);
          calloc.free(ssLen);
        }
      } finally {
        _ctxFree(ctx);
      }
    } finally {
      _pkeyFree(pubKeyPtr);
    }
  }

  /// Recover the shared secret from [ciphertext] using [secretKey].
  ///
  /// [secretKey] must be an 8-byte handle previously returned by
  /// [generateKeyPair] on **this same instance**, in the **same process**.
  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    final int handle = _decodeHandle(secretKey);
    final Pointer<EVP_PKEY>? pkey = _keys[handle];
    if (pkey == null) throw StateError('Unknown ML-KEM-768 key handle');

    final Pointer<EVP_PKEY_CTX> ctx = _ctxNew(pkey, nullptr);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new failed');
    try {
      if (_decapsInit(ctx, nullptr) <= 0) {
        throw StateError('EVP_PKEY_decapsulate_init failed');
      }

      final Pointer<IntPtr> ssLen = calloc<IntPtr>();
      final Pointer<Uint8> ctBuf = calloc<Uint8>(ciphertext.length);
      ctBuf.asTypedList(ciphertext.length).setAll(0, ciphertext);
      try {
        if (_decapsulate(ctx, nullptr, ssLen, ctBuf, ciphertext.length) <= 0) {
          throw StateError('EVP_PKEY_decapsulate size query failed');
        }
        final Pointer<Uint8> ssBuf = calloc<Uint8>(ssLen.value);
        try {
          if (_decapsulate(ctx, ssBuf, ssLen, ctBuf, ciphertext.length) <= 0) {
            throw StateError('EVP_PKEY_decapsulate failed');
          }
          return Uint8List.fromList(ssBuf.asTypedList(ssLen.value));
        } finally {
          calloc.free(ssBuf);
        }
      } finally {
        calloc.free(ssLen);
        calloc.free(ctBuf);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  /// Free the native EVP_PKEY associated with the handle held by [kp].
  void releaseKeyPair(({Uint8List publicKey, Uint8List secretKey}) kp) {
    final int handle = _decodeHandle(kp.secretKey);
    final Pointer<EVP_PKEY>? pkey = _keys.remove(handle);
    if (pkey != null) _pkeyFree(pkey);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Uint8List _extractPublicKeyBytes(Pointer<EVP_PKEY> pkey) {
    final Pointer<Pointer<Uint8>> ppub = calloc<Pointer<Uint8>>();
    try {
      final int len = _get1EncodedPubKey(pkey, ppub);
      if (len <= 0) {
        throw StateError('EVP_PKEY_get1_encoded_public_key failed');
      }
      final Uint8List bytes = Uint8List.fromList(ppub.value.asTypedList(len));
      _cryptoFree(ppub.value.cast(), nullptr, 0);
      return bytes;
    } finally {
      calloc.free(ppub);
    }
  }

  Pointer<EVP_PKEY> _importPublicKey(Uint8List pubKeyBytes) {
    final Pointer<Utf8> algName = 'ML-KEM-768'.toNativeUtf8();
    final Pointer<Utf8> paramName = 'pub'.toNativeUtf8();
    final Pointer<Uint8> keyBuf = calloc<Uint8>(pubKeyBytes.length);
    keyBuf.asTypedList(pubKeyBytes.length).setAll(0, pubKeyBytes);

    final Pointer<Pointer<EVP_PKEY>> pkeyPtr = calloc<Pointer<EVP_PKEY>>();
    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;

    try {
      final Pointer<OSSL_PARAM_BLD> bld = _bldNew();
      if (bld == nullptr) throw StateError('OSSL_PARAM_BLD_new failed');
      if (_bldPushOctet(bld, paramName, keyBuf, pubKeyBytes.length) <= 0) {
        _bldFree(bld);
        throw StateError('OSSL_PARAM_BLD_push_octet_string failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) {
        throw StateError('OSSL_PARAM_BLD_to_param failed');
      }

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) {
        throw StateError('EVP_PKEY_CTX_new_from_name failed');
      }
      if (_fromdataInit(ctx) <= 0) {
        throw StateError('EVP_PKEY_fromdata_init failed');
      }
      if (_fromdata(ctx, pkeyPtr, evpPkeyPublicKey, params) <= 0) {
        throw StateError('EVP_PKEY_fromdata failed');
      }
      return pkeyPtr.value;
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      calloc.free(keyBuf);
      calloc.free(paramName);
      calloc.free(algName);
      calloc.free(pkeyPtr);
    }
  }

  int _registerKey(Pointer<EVP_PKEY> pkey) {
    int handle;
    do {
      handle = _rng.nextInt(0x7fffffff) | (_rng.nextInt(0x7fffffff) << 32);
    } while (_keys.containsKey(handle));
    _keys[handle] = pkey;
    return handle;
  }

  static Uint8List _encodeHandle(int handle) {
    final Uint8List out = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      out[i] = (handle >> (8 * i)) & 0xff;
    }
    return out;
  }

  static int _decodeHandle(Uint8List bytes) {
    int h = 0;
    for (int i = 0; i < 8; i++) {
      h |= bytes[i] << (8 * i);
    }
    return h;
  }
}
