// OpenSSL ML-KEM-768 FFI wrapper.
//
// Loads libcrypto from a user-provided path, exposes a small Dart class around
// EVP_PKEY_CTX_new_from_name("ML-KEM-768") + keygen / encapsulate / decapsulate.
// Public keys are exchanged as raw bytes; secret keys are kept as opaque
// EVP_PKEY* pointers owned by the caller (must be freed with freeKey).
//
// Also re-exports the opaque EVP types so callers that build other EVP-backed
// primitives (e.g., ML-DSA, AEAD, KDF) can share the same dylib handle.

import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ── OpenSSL EVP opaque types ──────────────────────────────────────────────────
final class EVP_PKEY extends Opaque {}
final class EVP_PKEY_CTX extends Opaque {}
final class OSSL_PARAM extends Opaque {}
final class OSSL_PARAM_BLD extends Opaque {}

// ── FFI typedefs ─────────────────────────────────────────────────────────────

typedef EvpPkeyCtxNewFromNameNative = Pointer<EVP_PKEY_CTX> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>);
typedef EvpPkeyCtxNewFromNameDart = Pointer<EVP_PKEY_CTX> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>);

typedef EvpPkeyCtxNewNative = Pointer<EVP_PKEY_CTX> Function(
    Pointer<EVP_PKEY>, Pointer<Void>);
typedef EvpPkeyCtxNewDart = Pointer<EVP_PKEY_CTX> Function(
    Pointer<EVP_PKEY>, Pointer<Void>);

typedef EvpPkeyCtxFreeNative = Void Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyCtxFreeDart = void Function(Pointer<EVP_PKEY_CTX>);

typedef EvpPkeyFreeNative = Void Function(Pointer<EVP_PKEY>);
typedef EvpPkeyFreeDart = void Function(Pointer<EVP_PKEY>);

typedef EvpPkeyKeygenInitNative = Int32 Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyKeygenInitDart = int Function(Pointer<EVP_PKEY_CTX>);

typedef EvpPkeyKemInitNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Void>);
typedef EvpPkeyKemInitDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Void>);

typedef EvpPkeyFromdataInitNative = Int32 Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyFromdataInitDart = int Function(Pointer<EVP_PKEY_CTX>);

typedef EvpPkeyKeygenNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>);
typedef EvpPkeyKeygenDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>);

typedef EvpPkeyGet1EncodedPublicKeyNative = IntPtr Function(
    Pointer<EVP_PKEY>, Pointer<Pointer<Uint8>>);
typedef EvpPkeyGet1EncodedPublicKeyDart = int Function(
    Pointer<EVP_PKEY>, Pointer<Pointer<Uint8>>);

typedef EvpPkeyEncapsulateNative = Int32 Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, Pointer<IntPtr>);
typedef EvpPkeyEncapsulateDart = int Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, Pointer<IntPtr>);

typedef EvpPkeyDecapsulateNative = Int32 Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, IntPtr);
typedef EvpPkeyDecapsulateDart = int Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, int);

typedef OsslParamBldNewNative = Pointer<OSSL_PARAM_BLD> Function();
typedef OsslParamBldNewDart = Pointer<OSSL_PARAM_BLD> Function();

typedef OsslParamBldFreeNative = Void Function(Pointer<OSSL_PARAM_BLD>);
typedef OsslParamBldFreeDart = void Function(Pointer<OSSL_PARAM_BLD>);

typedef OsslParamBldToParamNative = Pointer<OSSL_PARAM> Function(
    Pointer<OSSL_PARAM_BLD>);
typedef OsslParamBldToParamDart = Pointer<OSSL_PARAM> Function(
    Pointer<OSSL_PARAM_BLD>);

typedef OsslParamBldPushOctetStringNative = Int32 Function(
    Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>, IntPtr);
typedef OsslParamBldPushOctetStringDart = int Function(
    Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>, int);

typedef OsslParamFreeNative = Void Function(Pointer<OSSL_PARAM>);
typedef OsslParamFreeDart = void Function(Pointer<OSSL_PARAM>);

typedef EvpPkeyFromdataNative = Int32 Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Pointer<EVP_PKEY>>, Int32, Pointer<OSSL_PARAM>);
typedef EvpPkeyFromdataDart = int Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Pointer<EVP_PKEY>>, int, Pointer<OSSL_PARAM>);

typedef CryptoFreeNative = Void Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef CryptoFreeDart = void Function(Pointer<Void>, Pointer<Utf8>, int);

typedef EvpPkeyCtxSetParamsNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<OSSL_PARAM>);
typedef EvpPkeyCtxSetParamsDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<OSSL_PARAM>);

// ── OpenSSL selection constants ───────────────────────────────────────────────
// OSSL_KEYMGMT_SELECT_ALL_PARAMETERS = 0x04 | 0x80 = 0x84
// EVP_PKEY_PUBLIC_KEY = ALL_PARAMETERS | PUBLIC_KEY(0x02) = 0x86
// EVP_PKEY_KEYPAIR    = ALL_PARAMETERS | PUBLIC_KEY | PRIVATE_KEY(0x01) = 0x87
const int evpPkeyPublicKey = 0x86;
const int evpPkeyKeypair = 0x87;

// ── OpenSSL FFI wrapper ───────────────────────────────────────────────────────
class OpenSslMlKem768 {
  final DynamicLibrary lib;

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
  late final EvpPkeyCtxSetParamsDart _setParams;

  OpenSslMlKem768.load(String path) : lib = DynamicLibrary.open(path) {
    _ctxNewFromName = lib.lookupFunction<EvpPkeyCtxNewFromNameNative,
        EvpPkeyCtxNewFromNameDart>('EVP_PKEY_CTX_new_from_name');
    _ctxNew = lib.lookupFunction<EvpPkeyCtxNewNative, EvpPkeyCtxNewDart>(
        'EVP_PKEY_CTX_new');
    _ctxFree = lib.lookupFunction<EvpPkeyCtxFreeNative, EvpPkeyCtxFreeDart>(
        'EVP_PKEY_CTX_free');
    _pkeyFree = lib.lookupFunction<EvpPkeyFreeNative, EvpPkeyFreeDart>(
        'EVP_PKEY_free');
    _keygenInit = lib.lookupFunction<EvpPkeyKeygenInitNative,
        EvpPkeyKeygenInitDart>('EVP_PKEY_keygen_init');
    _keygen = lib.lookupFunction<EvpPkeyKeygenNative, EvpPkeyKeygenDart>(
        'EVP_PKEY_keygen');
    _get1EncodedPubKey = lib.lookupFunction<EvpPkeyGet1EncodedPublicKeyNative,
        EvpPkeyGet1EncodedPublicKeyDart>('EVP_PKEY_get1_encoded_public_key');
    _encapsInit = lib.lookupFunction<EvpPkeyKemInitNative, EvpPkeyKemInitDart>(
        'EVP_PKEY_encapsulate_init');
    _encapsulate = lib.lookupFunction<EvpPkeyEncapsulateNative,
        EvpPkeyEncapsulateDart>('EVP_PKEY_encapsulate');
    _decapsInit = lib.lookupFunction<EvpPkeyKemInitNative, EvpPkeyKemInitDart>(
        'EVP_PKEY_decapsulate_init');
    _decapsulate = lib.lookupFunction<EvpPkeyDecapsulateNative,
        EvpPkeyDecapsulateDart>('EVP_PKEY_decapsulate');
    _bldNew = lib.lookupFunction<OsslParamBldNewNative, OsslParamBldNewDart>(
        'OSSL_PARAM_BLD_new');
    _bldFree = lib.lookupFunction<OsslParamBldFreeNative, OsslParamBldFreeDart>(
        'OSSL_PARAM_BLD_free');
    _bldToParam = lib.lookupFunction<OsslParamBldToParamNative,
        OsslParamBldToParamDart>('OSSL_PARAM_BLD_to_param');
    _bldPushOctet = lib.lookupFunction<OsslParamBldPushOctetStringNative,
        OsslParamBldPushOctetStringDart>('OSSL_PARAM_BLD_push_octet_string');
    _paramFree = lib.lookupFunction<OsslParamFreeNative, OsslParamFreeDart>(
        'OSSL_PARAM_free');
    _fromdataInit = lib.lookupFunction<EvpPkeyFromdataInitNative,
        EvpPkeyFromdataInitDart>('EVP_PKEY_fromdata_init');
    _fromdata = lib.lookupFunction<EvpPkeyFromdataNative, EvpPkeyFromdataDart>(
        'EVP_PKEY_fromdata');
    _cryptoFree = lib.lookupFunction<CryptoFreeNative, CryptoFreeDart>(
        'CRYPTO_free');
    _setParams = lib.lookupFunction<EvpPkeyCtxSetParamsNative,
        EvpPkeyCtxSetParamsDart>('EVP_PKEY_CTX_set_params');
  }

  /// Generate an ML-KEM-768 keypair. Returns (publicKeyBytes, EVP_PKEY*).
  /// Caller must free the returned EVP_PKEY* with [freeKey].
  (Uint8List, Pointer<EVP_PKEY>) generateKeypair() {
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final ctx = _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new_from_name failed');

    try {
      if (_keygenInit(ctx) <= 0) throw StateError('EVP_PKEY_keygen_init failed');
      final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('EVP_PKEY_keygen failed');
        final pkey = pkeyPtr.value;
        final pubKeyBytes = _extractPublicKeyBytes(pkey);
        return (pubKeyBytes, pkey);
      } finally {
        calloc.free(pkeyPtr);
      }
    } finally {
      _ctxFree(ctx);
    }
  }

  /// Extract the raw public key bytes from an EVP_PKEY.
  Uint8List _extractPublicKeyBytes(Pointer<EVP_PKEY> pkey) {
    final ppub = calloc<Pointer<Uint8>>();
    try {
      final len = _get1EncodedPubKey(pkey, ppub);
      if (len <= 0) throw StateError('EVP_PKEY_get1_encoded_public_key failed');
      final bytes = Uint8List.fromList(ppub.value.asTypedList(len));
      _cryptoFree(ppub.value.cast(), nullptr, 0);
      return bytes;
    } finally {
      calloc.free(ppub);
    }
  }

  /// Import a raw public key (1184 bytes) and return an EVP_PKEY*.
  /// Caller must free with [freeKey].
  Pointer<EVP_PKEY> importPublicKey(Uint8List pubKeyBytes) {
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final paramName = 'pub'.toNativeUtf8();
    final keyBuf = calloc<Uint8>(pubKeyBytes.length);
    keyBuf.asTypedList(pubKeyBytes.length).setAll(0, pubKeyBytes);

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();

    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('OSSL_PARAM_BLD_new failed');
      if (_bldPushOctet(bld, paramName, keyBuf, pubKeyBytes.length) <= 0) {
        _bldFree(bld);
        throw StateError('OSSL_PARAM_BLD_push_octet_string failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('OSSL_PARAM_BLD_to_param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new_from_name failed');

      if (_fromdataInit(ctx) <= 0) throw StateError('EVP_PKEY_fromdata_init failed');

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

  /// Encapsulate against a public EVP_PKEY*. Returns (ciphertext, sharedSecret).
  (Uint8List, Uint8List) encapsulate(Pointer<EVP_PKEY> pubKey) {
    final ctx = _ctxNew(pubKey, nullptr);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new failed');
    try {
      if (_encapsInit(ctx, nullptr) <= 0) throw StateError('EVP_PKEY_encapsulate_init failed');

      final ctLen = calloc<IntPtr>();
      final ssLen = calloc<IntPtr>();
      try {
        if (_encapsulate(ctx, nullptr, ctLen, nullptr, ssLen) <= 0) {
          throw StateError('EVP_PKEY_encapsulate (size query) failed');
        }

        final ctBuf = calloc<Uint8>(ctLen.value);
        final ssBuf = calloc<Uint8>(ssLen.value);
        try {
          if (_encapsulate(ctx, ctBuf, ctLen, ssBuf, ssLen) <= 0) {
            throw StateError('EVP_PKEY_encapsulate failed');
          }
          return (
            Uint8List.fromList(ctBuf.asTypedList(ctLen.value)),
            Uint8List.fromList(ssBuf.asTypedList(ssLen.value)),
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
  }

  /// Decapsulate using a full keypair EVP_PKEY*. Returns shared secret.
  Uint8List decapsulate(Pointer<EVP_PKEY> secretKey, Uint8List ciphertext) {
    final ctx = _ctxNew(secretKey, nullptr);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new failed');
    try {
      if (_decapsInit(ctx, nullptr) <= 0) throw StateError('EVP_PKEY_decapsulate_init failed');

      final ssLen = calloc<IntPtr>();
      final ctBuf = calloc<Uint8>(ciphertext.length);
      ctBuf.asTypedList(ciphertext.length).setAll(0, ciphertext);
      try {
        if (_decapsulate(ctx, nullptr, ssLen, ctBuf, ciphertext.length) <= 0) {
          throw StateError('EVP_PKEY_decapsulate (size query) failed');
        }
        final ssBuf = calloc<Uint8>(ssLen.value);
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

  /// Generate an ML-KEM-768 keypair deterministically from a 64-byte seed.
  /// Uses EVP_PKEY_CTX_set_params with "seed" (OpenSSL 3.5+).
  /// Returns (publicKeyBytes, EVP_PKEY*). Caller must free with [freeKey].
  (Uint8List, Pointer<EVP_PKEY>) keygenFromSeed(Uint8List seed64) {
    assert(seed64.length == 64, 'ML-KEM seed must be 64 bytes');
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final seedName = 'seed'.toNativeUtf8();
    final seedBuf = calloc<Uint8>(64);
    seedBuf.asTypedList(64).setAll(0, seed64);

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();

    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('ML-KEM keygenFromSeed: BLD_new failed');
      if (_bldPushOctet(bld, seedName, seedBuf, 64) <= 0) {
        _bldFree(bld);
        throw StateError('ML-KEM keygenFromSeed: push seed failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('ML-KEM keygenFromSeed: to_param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('ML-KEM keygenFromSeed: ctx new failed');
      if (_keygenInit(ctx) <= 0) throw StateError('ML-KEM keygenFromSeed: keygen_init failed');
      if (_setParams(ctx, params) <= 0) throw StateError('ML-KEM keygenFromSeed: set_params failed');
      if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('ML-KEM keygenFromSeed: keygen failed');

      final pkey = pkeyPtr.value;
      final pkBytes = _extractPublicKeyBytes(pkey);
      return (pkBytes, pkey);
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      calloc.free(seedBuf);
      calloc.free(seedName);
      calloc.free(algName);
      calloc.free(pkeyPtr);
    }
  }

  void freeKey(Pointer<EVP_PKEY> pkey) => _pkeyFree(pkey);

  /// Public wrapper for the private extract helper — needed when callers hold
  /// an EVP_PKEY* (e.g., one re-imported from SK bytes) and want the raw PK.
  Uint8List extractEncodedPublicKey(Pointer<EVP_PKEY> pkey) =>
      _extractPublicKeyBytes(pkey);

  // ── Secret-key serialization (for persistence) ────────────────────────────

  late final _getOctetStringParam = lib.lookupFunction<
      Int32 Function(Pointer<EVP_PKEY>, Pointer<Utf8>, Pointer<Uint8>, IntPtr,
          Pointer<IntPtr>),
      int Function(Pointer<EVP_PKEY>, Pointer<Utf8>, Pointer<Uint8>, int,
          Pointer<IntPtr>)>('EVP_PKEY_get_octet_string_param');

  /// Extract the raw secret-key bytes from an EVP_PKEY (for persistence).
  Uint8List extractSecretKeyBytes(Pointer<EVP_PKEY> pkey) {
    final name = 'priv'.toNativeUtf8();
    final outLen = calloc<IntPtr>();
    try {
      if (_getOctetStringParam(pkey, name, nullptr, 0, outLen) <= 0) {
        throw StateError('ML-KEM: get "priv" size query failed');
      }
      final buf = calloc<Uint8>(outLen.value);
      try {
        if (_getOctetStringParam(pkey, name, buf, outLen.value, outLen) <= 0) {
          throw StateError('ML-KEM: get "priv" failed');
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

  /// Import a previously serialized secret key (returns EVP_PKEY*).
  /// Caller must free with [freeKey].
  Pointer<EVP_PKEY> importSecretKey(Uint8List skBytes) {
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final paramName = 'priv'.toNativeUtf8();
    final keyBuf = calloc<Uint8>(skBytes.length);
    keyBuf.asTypedList(skBytes.length).setAll(0, skBytes);

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();

    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('ML-KEM importSk: BLD_new failed');
      if (_bldPushOctet(bld, paramName, keyBuf, skBytes.length) <= 0) {
        _bldFree(bld);
        throw StateError('ML-KEM importSk: push priv failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('ML-KEM importSk: to_param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('ML-KEM importSk: ctx new failed');
      if (_fromdataInit(ctx) <= 0) {
        throw StateError('ML-KEM importSk: fromdata_init failed');
      }
      if (_fromdata(ctx, pkeyPtr, evpPkeyKeypair, params) <= 0) {
        throw StateError('ML-KEM importSk: fromdata failed');
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
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String hex(List<int> bytes, {int maxBytes = 16}) {
  final shown = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  final h = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return bytes.length > maxBytes ? '$h... (${bytes.length} bytes)' : h;
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
