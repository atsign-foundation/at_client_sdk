// OpenSSL FFI primitives for demo 6.
//
// ML-KEM-768 comes from demo 3's package (no duplication).
// On top we add ML-DSA-65, AES-256-GCM, HKDF-SHA256, HMAC-SHA256, SHA-256, RAND.
// HPKE-style hybrid encryption is built in Dart on top of these primitives
// (no dependency on OpenSSL's OSSL_HPKE_* API — keeps the construction visible
// and avoids the question of whether OpenSSL 3.6's HPKE has ML-KEM support).

import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:demo_3/ml_kem.dart';

// Re-export so callers can see the ML-KEM API at one import.
export 'package:demo_3/ml_kem.dart' show OpenSslMlKem768, EVP_PKEY, hex, bytesEqual;

const String defaultLibCryptoPath =
    '/opt/homebrew/opt/openssl@3.6/lib/libcrypto.dylib';

// ── Additional EVP opaque types ───────────────────────────────────────────────
final class EVP_MD_CTX extends Opaque {}
final class EVP_CIPHER_CTX extends Opaque {}
final class EVP_CIPHER extends Opaque {}
final class EVP_MD extends Opaque {}
final class EVP_KDF extends Opaque {}
final class EVP_KDF_CTX extends Opaque {}
final class EVP_MAC extends Opaque {}
final class EVP_MAC_CTX extends Opaque {}

// ── Cipher constants ──────────────────────────────────────────────────────────
const int evpCtrlGcmGetTag = 0x10;
const int evpCtrlGcmSetTag = 0x11;
const int evpCtrlGcmSetIvlen = 0x9;

// ── ML-DSA-65 ────────────────────────────────────────────────────────────────
// Signature length is fixed at 3309 B for ML-DSA-65.
// PK is 1952 B, SK is 4032 B.

class MlDsa65 {
  final DynamicLibrary _lib;

  // Reuse the same EVP_PKEY function signatures defined in ml_kem.dart.
  // We declare local typedef aliases here to keep this file self-contained.
  late final Pointer<EVP_PKEY_CTX> Function(
      Pointer<Void>, Pointer<Utf8>, Pointer<Void>) _ctxNewFromName;
  late final void Function(Pointer<EVP_PKEY_CTX>) _ctxFree;
  late final void Function(Pointer<EVP_PKEY>) _pkeyFree;
  late final int Function(Pointer<EVP_PKEY_CTX>) _keygenInit;
  late final int Function(
      Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>) _keygen;

  // EVP_MD_CTX_new / free / sign / verify
  late final Pointer<EVP_MD_CTX> Function() _mdCtxNew;
  late final void Function(Pointer<EVP_MD_CTX>) _mdCtxFree;
  late final int Function(
      Pointer<EVP_MD_CTX>,
      Pointer<Pointer<EVP_PKEY_CTX>>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<EVP_PKEY>,
      Pointer<Void>) _digestSignInitEx;
  late final int Function(
      Pointer<EVP_MD_CTX>,
      Pointer<Pointer<EVP_PKEY_CTX>>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<EVP_PKEY>,
      Pointer<Void>) _digestVerifyInitEx;
  late final int Function(Pointer<EVP_MD_CTX>, Pointer<Uint8>, Pointer<IntPtr>,
      Pointer<Uint8>, int) _digestSign;
  late final int Function(Pointer<EVP_MD_CTX>, Pointer<Uint8>, int,
      Pointer<Uint8>, int) _digestVerify;

  // For raw key export/import via "priv" / "pub" OSSL_PARAMs
  late final int Function(
      Pointer<EVP_PKEY>, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<IntPtr>) _getOctetStringParam;
  late final Pointer<OSSL_PARAM_BLD> Function() _bldNew;
  late final void Function(Pointer<OSSL_PARAM_BLD>) _bldFree;
  late final Pointer<OSSL_PARAM> Function(Pointer<OSSL_PARAM_BLD>) _bldToParam;
  late final int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>,
      int) _bldPushOctet;
  late final void Function(Pointer<OSSL_PARAM>) _paramFree;
  late final int Function(Pointer<EVP_PKEY_CTX>) _fromdataInit;
  late final int Function(Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>,
      int, Pointer<OSSL_PARAM>) _fromdata;

  MlDsa65(this._lib) {
    _ctxNewFromName = _lib.lookupFunction<
        Pointer<EVP_PKEY_CTX> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Void>),
        Pointer<EVP_PKEY_CTX> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Void>)>(
        'EVP_PKEY_CTX_new_from_name');
    _ctxFree = _lib.lookupFunction<Void Function(Pointer<EVP_PKEY_CTX>),
        void Function(Pointer<EVP_PKEY_CTX>)>('EVP_PKEY_CTX_free');
    _pkeyFree = _lib.lookupFunction<Void Function(Pointer<EVP_PKEY>),
        void Function(Pointer<EVP_PKEY>)>('EVP_PKEY_free');
    _keygenInit = _lib.lookupFunction<Int32 Function(Pointer<EVP_PKEY_CTX>),
        int Function(Pointer<EVP_PKEY_CTX>)>('EVP_PKEY_keygen_init');
    _keygen = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>),
        int Function(Pointer<EVP_PKEY_CTX>,
            Pointer<Pointer<EVP_PKEY>>)>('EVP_PKEY_keygen');
    _mdCtxNew = _lib.lookupFunction<Pointer<EVP_MD_CTX> Function(),
        Pointer<EVP_MD_CTX> Function()>('EVP_MD_CTX_new');
    _mdCtxFree = _lib.lookupFunction<Void Function(Pointer<EVP_MD_CTX>),
        void Function(Pointer<EVP_MD_CTX>)>('EVP_MD_CTX_free');
    _digestSignInitEx = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_MD_CTX>,
            Pointer<Pointer<EVP_PKEY_CTX>>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<EVP_PKEY>,
            Pointer<Void>),
        int Function(
            Pointer<EVP_MD_CTX>,
            Pointer<Pointer<EVP_PKEY_CTX>>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<EVP_PKEY>,
            Pointer<Void>)>('EVP_DigestSignInit_ex');
    _digestVerifyInitEx = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_MD_CTX>,
            Pointer<Pointer<EVP_PKEY_CTX>>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<EVP_PKEY>,
            Pointer<Void>),
        int Function(
            Pointer<EVP_MD_CTX>,
            Pointer<Pointer<EVP_PKEY_CTX>>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<EVP_PKEY>,
            Pointer<Void>)>('EVP_DigestVerifyInit_ex');
    _digestSign = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_MD_CTX>, Pointer<Uint8>, Pointer<IntPtr>,
            Pointer<Uint8>, IntPtr),
        int Function(Pointer<EVP_MD_CTX>, Pointer<Uint8>, Pointer<IntPtr>,
            Pointer<Uint8>, int)>('EVP_DigestSign');
    _digestVerify = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_MD_CTX>, Pointer<Uint8>, IntPtr,
            Pointer<Uint8>, IntPtr),
        int Function(Pointer<EVP_MD_CTX>, Pointer<Uint8>, int, Pointer<Uint8>,
            int)>('EVP_DigestVerify');
    _getOctetStringParam = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_PKEY>, Pointer<Utf8>, Pointer<Uint8>, IntPtr,
            Pointer<IntPtr>),
        int Function(Pointer<EVP_PKEY>, Pointer<Utf8>, Pointer<Uint8>, int,
            Pointer<IntPtr>)>('EVP_PKEY_get_octet_string_param');
    _bldNew = _lib.lookupFunction<Pointer<OSSL_PARAM_BLD> Function(),
        Pointer<OSSL_PARAM_BLD> Function()>('OSSL_PARAM_BLD_new');
    _bldFree = _lib.lookupFunction<Void Function(Pointer<OSSL_PARAM_BLD>),
        void Function(Pointer<OSSL_PARAM_BLD>)>('OSSL_PARAM_BLD_free');
    _bldToParam = _lib.lookupFunction<
        Pointer<OSSL_PARAM> Function(Pointer<OSSL_PARAM_BLD>),
        Pointer<OSSL_PARAM> Function(
            Pointer<OSSL_PARAM_BLD>)>('OSSL_PARAM_BLD_to_param');
    _bldPushOctet = _lib.lookupFunction<
        Int32 Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>,
            IntPtr),
        int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>,
            int)>('OSSL_PARAM_BLD_push_octet_string');
    _paramFree = _lib.lookupFunction<Void Function(Pointer<OSSL_PARAM>),
        void Function(Pointer<OSSL_PARAM>)>('OSSL_PARAM_free');
    _fromdataInit = _lib.lookupFunction<Int32 Function(Pointer<EVP_PKEY_CTX>),
        int Function(Pointer<EVP_PKEY_CTX>)>('EVP_PKEY_fromdata_init');
    _fromdata = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>,
            Int32, Pointer<OSSL_PARAM>),
        int Function(Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>, int,
            Pointer<OSSL_PARAM>)>('EVP_PKEY_fromdata');
  }

  /// Generate keypair. Returns (pkBytes, skBytes) — both fully serialized,
  /// usable with importPublicKey / importSecretKey.
  (Uint8List pk, Uint8List sk) generateKeypair() {
    final algName = 'ML-DSA-65'.toNativeUtf8();
    final ctx = _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('ML-DSA: EVP_PKEY_CTX_new_from_name failed');
    try {
      if (_keygenInit(ctx) <= 0) throw StateError('ML-DSA: keygen_init failed');
      final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) {
          throw StateError('ML-DSA: keygen failed');
        }
        final pkey = pkeyPtr.value;
        try {
          final pk = _extractParam(pkey, 'pub');
          final sk = _extractParam(pkey, 'priv');
          return (pk, sk);
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

  Uint8List _extractParam(Pointer<EVP_PKEY> pkey, String paramName) {
    final name = paramName.toNativeUtf8();
    final outLen = calloc<IntPtr>();
    try {
      // Size query
      if (_getOctetStringParam(pkey, name, nullptr, 0, outLen) <= 0) {
        throw StateError('ML-DSA: get param "$paramName" size query failed');
      }
      final buf = calloc<Uint8>(outLen.value);
      try {
        if (_getOctetStringParam(pkey, name, buf, outLen.value, outLen) <= 0) {
          throw StateError('ML-DSA: get param "$paramName" failed');
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

  /// Import a serialized key into an EVP_PKEY. paramName must be "pub" or "priv".
  /// Selection must be evpPkeyPublicKey or evpPkeyKeypair from ml_kem.dart.
  Pointer<EVP_PKEY> _importKey(
      Uint8List keyBytes, String paramName, int selection) {
    final algName = 'ML-DSA-65'.toNativeUtf8();
    final pname = paramName.toNativeUtf8();
    final keyBuf = calloc<Uint8>(keyBytes.length);
    keyBuf.asTypedList(keyBytes.length).setAll(0, keyBytes);

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('ML-DSA: OSSL_PARAM_BLD_new failed');
      if (_bldPushOctet(bld, pname, keyBuf, keyBytes.length) <= 0) {
        _bldFree(bld);
        throw StateError('ML-DSA: bld push octet failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('ML-DSA: bld to param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('ML-DSA: ctx new from name failed');
      if (_fromdataInit(ctx) <= 0) {
        throw StateError('ML-DSA: fromdata_init failed');
      }
      if (_fromdata(ctx, pkeyPtr, selection, params) <= 0) {
        throw StateError('ML-DSA: fromdata failed');
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

  /// Sign `message` with serialized secret key bytes. Returns the signature.
  Uint8List sign(Uint8List skBytes, Uint8List message) {
    final pkey = _importKey(skBytes, 'priv', evpPkeyKeypair);
    try {
      final mdCtx = _mdCtxNew();
      if (mdCtx == nullptr) throw StateError('ML-DSA: MD_CTX_new failed');
      try {
        if (_digestSignInitEx(mdCtx, nullptr, nullptr, nullptr, nullptr, pkey,
                nullptr) <=
            0) {
          throw StateError('ML-DSA: DigestSignInit_ex failed');
        }
        final msgBuf = calloc<Uint8>(message.length);
        msgBuf.asTypedList(message.length).setAll(0, message);
        final sigLen = calloc<IntPtr>();
        try {
          if (_digestSign(mdCtx, nullptr, sigLen, msgBuf, message.length) <= 0) {
            throw StateError('ML-DSA: DigestSign (size query) failed');
          }
          final sigBuf = calloc<Uint8>(sigLen.value);
          try {
            if (_digestSign(mdCtx, sigBuf, sigLen, msgBuf, message.length) <=
                0) {
              throw StateError('ML-DSA: DigestSign failed');
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

  /// Verify a signature against `message` with serialized public key bytes.
  bool verify(Uint8List pkBytes, Uint8List message, Uint8List signature) {
    final pkey = _importKey(pkBytes, 'pub', evpPkeyPublicKey);
    try {
      final mdCtx = _mdCtxNew();
      if (mdCtx == nullptr) throw StateError('ML-DSA: MD_CTX_new failed');
      try {
        if (_digestVerifyInitEx(mdCtx, nullptr, nullptr, nullptr, nullptr, pkey,
                nullptr) <=
            0) {
          throw StateError('ML-DSA: DigestVerifyInit_ex failed');
        }
        final msgBuf = calloc<Uint8>(message.length);
        msgBuf.asTypedList(message.length).setAll(0, message);
        final sigBuf = calloc<Uint8>(signature.length);
        sigBuf.asTypedList(signature.length).setAll(0, signature);
        try {
          final rc = _digestVerify(
              mdCtx, sigBuf, signature.length, msgBuf, message.length);
          return rc == 1;
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
}

// ── AES-256-GCM ──────────────────────────────────────────────────────────────
class AesGcm {
  final DynamicLibrary _lib;

  late final Pointer<EVP_CIPHER_CTX> Function() _ctxNew;
  late final void Function(Pointer<EVP_CIPHER_CTX>) _ctxFree;
  late final Pointer<EVP_CIPHER> Function(Pointer<Void>, Pointer<Utf8>,
      Pointer<Utf8>) _cipherFetch;
  late final void Function(Pointer<EVP_CIPHER>) _cipherFree;
  late final int Function(
      Pointer<EVP_CIPHER_CTX>,
      Pointer<EVP_CIPHER>,
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Uint8>) _encryptInitEx;
  late final int Function(
      Pointer<EVP_CIPHER_CTX>,
      Pointer<EVP_CIPHER>,
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Uint8>) _decryptInitEx;
  late final int Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>,
      Pointer<Int32>, Pointer<Uint8>, int) _encryptUpdate;
  late final int Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>,
      Pointer<Int32>, Pointer<Uint8>, int) _decryptUpdate;
  late final int Function(
      Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>) _encryptFinal;
  late final int Function(
      Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>) _decryptFinal;
  late final int Function(
      Pointer<EVP_CIPHER_CTX>, int, int, Pointer<Void>) _ctxCtrl;

  AesGcm(this._lib) {
    _ctxNew = _lib.lookupFunction<Pointer<EVP_CIPHER_CTX> Function(),
        Pointer<EVP_CIPHER_CTX> Function()>('EVP_CIPHER_CTX_new');
    _ctxFree = _lib.lookupFunction<Void Function(Pointer<EVP_CIPHER_CTX>),
        void Function(Pointer<EVP_CIPHER_CTX>)>('EVP_CIPHER_CTX_free');
    _cipherFetch = _lib.lookupFunction<
        Pointer<EVP_CIPHER> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<EVP_CIPHER> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('EVP_CIPHER_fetch');
    _cipherFree = _lib.lookupFunction<Void Function(Pointer<EVP_CIPHER>),
        void Function(Pointer<EVP_CIPHER>)>('EVP_CIPHER_free');
    // Use EVP_EncryptInit_ex (legacy 5-arg form): ctx, cipher, ENGINE* (NULL), key, iv.
    _encryptInitEx = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_CIPHER_CTX>,
            Pointer<EVP_CIPHER>,
            Pointer<Void>,
            Pointer<Uint8>,
            Pointer<Uint8>),
        int Function(
            Pointer<EVP_CIPHER_CTX>,
            Pointer<EVP_CIPHER>,
            Pointer<Void>,
            Pointer<Uint8>,
            Pointer<Uint8>)>('EVP_EncryptInit_ex');
    _decryptInitEx = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_CIPHER_CTX>,
            Pointer<EVP_CIPHER>,
            Pointer<Void>,
            Pointer<Uint8>,
            Pointer<Uint8>),
        int Function(
            Pointer<EVP_CIPHER_CTX>,
            Pointer<EVP_CIPHER>,
            Pointer<Void>,
            Pointer<Uint8>,
            Pointer<Uint8>)>('EVP_DecryptInit_ex');
    _encryptUpdate = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>,
            Pointer<Uint8>, Int32),
        int Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>,
            Pointer<Uint8>, int)>('EVP_EncryptUpdate');
    _decryptUpdate = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>,
            Pointer<Uint8>, Int32),
        int Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>,
            Pointer<Uint8>, int)>('EVP_DecryptUpdate');
    _encryptFinal = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>),
        int Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>,
            Pointer<Int32>)>('EVP_EncryptFinal_ex');
    _decryptFinal = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>, Pointer<Int32>),
        int Function(Pointer<EVP_CIPHER_CTX>, Pointer<Uint8>,
            Pointer<Int32>)>('EVP_DecryptFinal_ex');
    _ctxCtrl = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_CIPHER_CTX>, Int32, Int32, Pointer<Void>),
        int Function(Pointer<EVP_CIPHER_CTX>, int, int,
            Pointer<Void>)>('EVP_CIPHER_CTX_ctrl');
  }

  /// AES-256-GCM seal. nonce must be 12 bytes. Returns (ciphertext, tag(16B)).
  (Uint8List ct, Uint8List tag) seal(
      Uint8List key, Uint8List nonce, Uint8List plaintext,
      {Uint8List? aad}) {
    if (key.length != 32) throw ArgumentError('AES-256-GCM key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('AES-GCM nonce must be 12 bytes');
    final algName = 'AES-256-GCM'.toNativeUtf8();
    final cipher = _cipherFetch(nullptr, algName, nullptr);
    calloc.free(algName);
    if (cipher == nullptr) throw StateError('AES-GCM: cipher fetch failed');

    final ctx = _ctxNew();
    if (ctx == nullptr) {
      _cipherFree(cipher);
      throw StateError('AES-GCM: ctx new failed');
    }

    final keyBuf = calloc<Uint8>(32);
    final nonceBuf = calloc<Uint8>(12);
    final ctBuf = calloc<Uint8>(plaintext.length + 16);
    final tagBuf = calloc<Uint8>(16);
    final outlen = calloc<Int32>();
    Pointer<Uint8>? ptBuf;
    Pointer<Uint8>? aadBuf;

    try {
      keyBuf.asTypedList(32).setAll(0, key);
      nonceBuf.asTypedList(12).setAll(0, nonce);

      if (_encryptInitEx(ctx, cipher, nullptr, keyBuf, nonceBuf) <= 0) {
        throw StateError('AES-GCM: EncryptInit_ex2 failed');
      }

      if (aad != null && aad.isNotEmpty) {
        aadBuf = calloc<Uint8>(aad.length);
        aadBuf.asTypedList(aad.length).setAll(0, aad);
        if (_encryptUpdate(ctx, nullptr, outlen, aadBuf, aad.length) <= 0) {
          throw StateError('AES-GCM: AAD update failed');
        }
      }

      ptBuf = calloc<Uint8>(plaintext.length);
      ptBuf.asTypedList(plaintext.length).setAll(0, plaintext);
      if (_encryptUpdate(ctx, ctBuf, outlen, ptBuf, plaintext.length) <= 0) {
        throw StateError('AES-GCM: EncryptUpdate failed');
      }
      final partial1 = outlen.value;

      if (_encryptFinal(ctx, (ctBuf + partial1), outlen) <= 0) {
        throw StateError('AES-GCM: EncryptFinal failed');
      }
      final ctLen = partial1 + outlen.value;

      if (_ctxCtrl(ctx, evpCtrlGcmGetTag, 16, tagBuf.cast()) <= 0) {
        throw StateError('AES-GCM: get tag failed');
      }

      final ct = Uint8List.fromList(ctBuf.asTypedList(ctLen));
      final tag = Uint8List.fromList(tagBuf.asTypedList(16));
      return (ct, tag);
    } finally {
      if (ptBuf != null) calloc.free(ptBuf);
      if (aadBuf != null) calloc.free(aadBuf);
      calloc.free(outlen);
      calloc.free(tagBuf);
      calloc.free(ctBuf);
      calloc.free(nonceBuf);
      calloc.free(keyBuf);
      _ctxFree(ctx);
      _cipherFree(cipher);
    }
  }

  /// AES-256-GCM open. Returns plaintext or throws on tag mismatch.
  Uint8List open(Uint8List key, Uint8List nonce, Uint8List ct, Uint8List tag,
      {Uint8List? aad}) {
    if (key.length != 32) throw ArgumentError('AES-256-GCM key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('AES-GCM nonce must be 12 bytes');
    if (tag.length != 16) throw ArgumentError('AES-GCM tag must be 16 bytes');
    final algName = 'AES-256-GCM'.toNativeUtf8();
    final cipher = _cipherFetch(nullptr, algName, nullptr);
    calloc.free(algName);
    if (cipher == nullptr) throw StateError('AES-GCM: cipher fetch failed');

    final ctx = _ctxNew();
    if (ctx == nullptr) {
      _cipherFree(cipher);
      throw StateError('AES-GCM: ctx new failed');
    }

    final keyBuf = calloc<Uint8>(32);
    final nonceBuf = calloc<Uint8>(12);
    final ptBuf = calloc<Uint8>(ct.length + 16);
    final tagBuf = calloc<Uint8>(16);
    final outlen = calloc<Int32>();
    Pointer<Uint8>? ctBufIn;
    Pointer<Uint8>? aadBuf;

    try {
      keyBuf.asTypedList(32).setAll(0, key);
      nonceBuf.asTypedList(12).setAll(0, nonce);
      tagBuf.asTypedList(16).setAll(0, tag);

      if (_decryptInitEx(ctx, cipher, nullptr, keyBuf, nonceBuf) <= 0) {
        throw StateError('AES-GCM: DecryptInit_ex2 failed');
      }

      if (aad != null && aad.isNotEmpty) {
        aadBuf = calloc<Uint8>(aad.length);
        aadBuf.asTypedList(aad.length).setAll(0, aad);
        if (_decryptUpdate(ctx, nullptr, outlen, aadBuf, aad.length) <= 0) {
          throw StateError('AES-GCM: AAD update failed');
        }
      }

      ctBufIn = calloc<Uint8>(ct.length);
      ctBufIn.asTypedList(ct.length).setAll(0, ct);
      if (_decryptUpdate(ctx, ptBuf, outlen, ctBufIn, ct.length) <= 0) {
        throw StateError('AES-GCM: DecryptUpdate failed');
      }
      final partial1 = outlen.value;

      // Set the expected tag before Final
      if (_ctxCtrl(ctx, evpCtrlGcmSetTag, 16, tagBuf.cast()) <= 0) {
        throw StateError('AES-GCM: set tag failed');
      }

      if (_decryptFinal(ctx, (ptBuf + partial1), outlen) <= 0) {
        throw StateError('AES-GCM: DecryptFinal failed (auth tag mismatch?)');
      }
      final ptLen = partial1 + outlen.value;

      return Uint8List.fromList(ptBuf.asTypedList(ptLen));
    } finally {
      if (ctBufIn != null) calloc.free(ctBufIn);
      if (aadBuf != null) calloc.free(aadBuf);
      calloc.free(outlen);
      calloc.free(tagBuf);
      calloc.free(ptBuf);
      calloc.free(nonceBuf);
      calloc.free(keyBuf);
      _ctxFree(ctx);
      _cipherFree(cipher);
    }
  }
}

// ── HKDF-SHA256 ──────────────────────────────────────────────────────────────
class Hkdf {
  final DynamicLibrary _lib;

  late final Pointer<EVP_KDF> Function(Pointer<Void>, Pointer<Utf8>,
      Pointer<Utf8>) _kdfFetch;
  late final void Function(Pointer<EVP_KDF>) _kdfFree;
  late final Pointer<EVP_KDF_CTX> Function(Pointer<EVP_KDF>) _kdfCtxNew;
  late final void Function(Pointer<EVP_KDF_CTX>) _kdfCtxFree;
  late final int Function(Pointer<EVP_KDF_CTX>, Pointer<Uint8>, int,
      Pointer<OSSL_PARAM>) _kdfDerive;
  late final Pointer<OSSL_PARAM_BLD> Function() _bldNew;
  late final void Function(Pointer<OSSL_PARAM_BLD>) _bldFree;
  late final Pointer<OSSL_PARAM> Function(Pointer<OSSL_PARAM_BLD>) _bldToParam;
  late final int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Utf8>,
      int) _bldPushUtf8;
  late final int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>,
      int) _bldPushOctet;
  late final void Function(Pointer<OSSL_PARAM>) _paramFree;

  Hkdf(this._lib) {
    _kdfFetch = _lib.lookupFunction<
        Pointer<EVP_KDF> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<EVP_KDF> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('EVP_KDF_fetch');
    _kdfFree = _lib.lookupFunction<Void Function(Pointer<EVP_KDF>),
        void Function(Pointer<EVP_KDF>)>('EVP_KDF_free');
    _kdfCtxNew = _lib.lookupFunction<
        Pointer<EVP_KDF_CTX> Function(Pointer<EVP_KDF>),
        Pointer<EVP_KDF_CTX> Function(Pointer<EVP_KDF>)>('EVP_KDF_CTX_new');
    _kdfCtxFree = _lib.lookupFunction<Void Function(Pointer<EVP_KDF_CTX>),
        void Function(Pointer<EVP_KDF_CTX>)>('EVP_KDF_CTX_free');
    _kdfDerive = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_KDF_CTX>, Pointer<Uint8>, IntPtr,
            Pointer<OSSL_PARAM>),
        int Function(Pointer<EVP_KDF_CTX>, Pointer<Uint8>, int,
            Pointer<OSSL_PARAM>)>('EVP_KDF_derive');
    _bldNew = _lib.lookupFunction<Pointer<OSSL_PARAM_BLD> Function(),
        Pointer<OSSL_PARAM_BLD> Function()>('OSSL_PARAM_BLD_new');
    _bldFree = _lib.lookupFunction<Void Function(Pointer<OSSL_PARAM_BLD>),
        void Function(Pointer<OSSL_PARAM_BLD>)>('OSSL_PARAM_BLD_free');
    _bldToParam = _lib.lookupFunction<
        Pointer<OSSL_PARAM> Function(Pointer<OSSL_PARAM_BLD>),
        Pointer<OSSL_PARAM> Function(
            Pointer<OSSL_PARAM_BLD>)>('OSSL_PARAM_BLD_to_param');
    _bldPushUtf8 = _lib.lookupFunction<
        Int32 Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Utf8>,
            IntPtr),
        int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Utf8>,
            int)>('OSSL_PARAM_BLD_push_utf8_string');
    _bldPushOctet = _lib.lookupFunction<
        Int32 Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>,
            IntPtr),
        int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Uint8>,
            int)>('OSSL_PARAM_BLD_push_octet_string');
    _paramFree = _lib.lookupFunction<Void Function(Pointer<OSSL_PARAM>),
        void Function(Pointer<OSSL_PARAM>)>('OSSL_PARAM_free');
  }

  /// HKDF-SHA256(salt, ikm, info) → outLen bytes.
  Uint8List derive(Uint8List salt, Uint8List ikm, Uint8List info, int outLen) {
    final kdfName = 'HKDF'.toNativeUtf8();
    final digestParam = 'digest'.toNativeUtf8();
    final digestVal = 'SHA256'.toNativeUtf8();
    final saltParam = 'salt'.toNativeUtf8();
    final keyParam = 'key'.toNativeUtf8();
    final infoParam = 'info'.toNativeUtf8();

    final kdf = _kdfFetch(nullptr, kdfName, nullptr);
    if (kdf == nullptr) {
      calloc.free(kdfName);
      throw StateError('HKDF: kdf fetch failed');
    }
    final ctx = _kdfCtxNew(kdf);
    if (ctx == nullptr) {
      _kdfFree(kdf);
      calloc.free(kdfName);
      throw StateError('HKDF: ctx new failed');
    }

    final saltBuf = calloc<Uint8>(salt.isEmpty ? 1 : salt.length);
    final ikmBuf = calloc<Uint8>(ikm.length);
    final infoBuf = calloc<Uint8>(info.isEmpty ? 1 : info.length);
    final outBuf = calloc<Uint8>(outLen);
    Pointer<OSSL_PARAM>? params;
    try {
      if (salt.isNotEmpty) saltBuf.asTypedList(salt.length).setAll(0, salt);
      ikmBuf.asTypedList(ikm.length).setAll(0, ikm);
      if (info.isNotEmpty) infoBuf.asTypedList(info.length).setAll(0, info);

      final bld = _bldNew();
      if (bld == nullptr) throw StateError('HKDF: bld new failed');
      if (_bldPushUtf8(bld, digestParam, digestVal, 6) <= 0) {
        _bldFree(bld);
        throw StateError('HKDF: push digest failed');
      }
      if (_bldPushOctet(bld, saltParam, saltBuf, salt.length) <= 0) {
        _bldFree(bld);
        throw StateError('HKDF: push salt failed');
      }
      if (_bldPushOctet(bld, keyParam, ikmBuf, ikm.length) <= 0) {
        _bldFree(bld);
        throw StateError('HKDF: push key failed');
      }
      if (_bldPushOctet(bld, infoParam, infoBuf, info.length) <= 0) {
        _bldFree(bld);
        throw StateError('HKDF: push info failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('HKDF: bld to param failed');

      if (_kdfDerive(ctx, outBuf, outLen, params) <= 0) {
        throw StateError('HKDF: derive failed');
      }
      return Uint8List.fromList(outBuf.asTypedList(outLen));
    } finally {
      if (params != null) _paramFree(params);
      calloc.free(outBuf);
      calloc.free(infoBuf);
      calloc.free(ikmBuf);
      calloc.free(saltBuf);
      calloc.free(infoParam);
      calloc.free(keyParam);
      calloc.free(saltParam);
      calloc.free(digestVal);
      calloc.free(digestParam);
      _kdfCtxFree(ctx);
      _kdfFree(kdf);
      calloc.free(kdfName);
    }
  }
}

// ── HMAC-SHA256 ──────────────────────────────────────────────────────────────
class HmacSha256 {
  final DynamicLibrary _lib;

  late final Pointer<EVP_MAC> Function(Pointer<Void>, Pointer<Utf8>,
      Pointer<Utf8>) _macFetch;
  late final void Function(Pointer<EVP_MAC>) _macFree;
  late final Pointer<EVP_MAC_CTX> Function(Pointer<EVP_MAC>) _macCtxNew;
  late final void Function(Pointer<EVP_MAC_CTX>) _macCtxFree;
  late final int Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, int,
      Pointer<OSSL_PARAM>) _macInit;
  late final int Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, int) _macUpdate;
  late final int Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>,
      Pointer<IntPtr>, int) _macFinal;
  late final Pointer<OSSL_PARAM_BLD> Function() _bldNew;
  late final void Function(Pointer<OSSL_PARAM_BLD>) _bldFree;
  late final Pointer<OSSL_PARAM> Function(Pointer<OSSL_PARAM_BLD>) _bldToParam;
  late final int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Utf8>,
      int) _bldPushUtf8;
  late final void Function(Pointer<OSSL_PARAM>) _paramFree;

  HmacSha256(this._lib) {
    _macFetch = _lib.lookupFunction<
        Pointer<EVP_MAC> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<EVP_MAC> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('EVP_MAC_fetch');
    _macFree = _lib.lookupFunction<Void Function(Pointer<EVP_MAC>),
        void Function(Pointer<EVP_MAC>)>('EVP_MAC_free');
    _macCtxNew = _lib.lookupFunction<
        Pointer<EVP_MAC_CTX> Function(Pointer<EVP_MAC>),
        Pointer<EVP_MAC_CTX> Function(Pointer<EVP_MAC>)>('EVP_MAC_CTX_new');
    _macCtxFree = _lib.lookupFunction<Void Function(Pointer<EVP_MAC_CTX>),
        void Function(Pointer<EVP_MAC_CTX>)>('EVP_MAC_CTX_free');
    _macInit = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, IntPtr,
            Pointer<OSSL_PARAM>),
        int Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, int,
            Pointer<OSSL_PARAM>)>('EVP_MAC_init');
    _macUpdate = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, IntPtr),
        int Function(
            Pointer<EVP_MAC_CTX>, Pointer<Uint8>, int)>('EVP_MAC_update');
    _macFinal = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, Pointer<IntPtr>,
            IntPtr),
        int Function(Pointer<EVP_MAC_CTX>, Pointer<Uint8>, Pointer<IntPtr>,
            int)>('EVP_MAC_final');
    _bldNew = _lib.lookupFunction<Pointer<OSSL_PARAM_BLD> Function(),
        Pointer<OSSL_PARAM_BLD> Function()>('OSSL_PARAM_BLD_new');
    _bldFree = _lib.lookupFunction<Void Function(Pointer<OSSL_PARAM_BLD>),
        void Function(Pointer<OSSL_PARAM_BLD>)>('OSSL_PARAM_BLD_free');
    _bldToParam = _lib.lookupFunction<
        Pointer<OSSL_PARAM> Function(Pointer<OSSL_PARAM_BLD>),
        Pointer<OSSL_PARAM> Function(
            Pointer<OSSL_PARAM_BLD>)>('OSSL_PARAM_BLD_to_param');
    _bldPushUtf8 = _lib.lookupFunction<
        Int32 Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Utf8>,
            IntPtr),
        int Function(Pointer<OSSL_PARAM_BLD>, Pointer<Utf8>, Pointer<Utf8>,
            int)>('OSSL_PARAM_BLD_push_utf8_string');
    _paramFree = _lib.lookupFunction<Void Function(Pointer<OSSL_PARAM>),
        void Function(Pointer<OSSL_PARAM>)>('OSSL_PARAM_free');
  }

  Uint8List mac(Uint8List key, Uint8List data) {
    final macName = 'HMAC'.toNativeUtf8();
    final digestParam = 'digest'.toNativeUtf8();
    final digestVal = 'SHA256'.toNativeUtf8();
    final mac = _macFetch(nullptr, macName, nullptr);
    if (mac == nullptr) {
      calloc.free(macName);
      throw StateError('HMAC: fetch failed');
    }
    final ctx = _macCtxNew(mac);
    if (ctx == nullptr) {
      _macFree(mac);
      calloc.free(macName);
      throw StateError('HMAC: ctx new failed');
    }

    final keyBuf = calloc<Uint8>(key.isEmpty ? 1 : key.length);
    final dataBuf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final out = calloc<Uint8>(32);
    final outLen = calloc<IntPtr>();
    Pointer<OSSL_PARAM>? params;
    try {
      if (key.isNotEmpty) keyBuf.asTypedList(key.length).setAll(0, key);
      if (data.isNotEmpty) dataBuf.asTypedList(data.length).setAll(0, data);

      final bld = _bldNew();
      if (bld == nullptr) throw StateError('HMAC: bld new failed');
      if (_bldPushUtf8(bld, digestParam, digestVal, 6) <= 0) {
        _bldFree(bld);
        throw StateError('HMAC: push digest failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);

      if (_macInit(ctx, keyBuf, key.length, params) <= 0) {
        throw StateError('HMAC: init failed');
      }
      if (data.isNotEmpty && _macUpdate(ctx, dataBuf, data.length) <= 0) {
        throw StateError('HMAC: update failed');
      }
      if (_macFinal(ctx, out, outLen, 32) <= 0) {
        throw StateError('HMAC: final failed');
      }
      return Uint8List.fromList(out.asTypedList(outLen.value));
    } finally {
      if (params != null) _paramFree(params);
      calloc.free(outLen);
      calloc.free(out);
      calloc.free(dataBuf);
      calloc.free(keyBuf);
      calloc.free(digestVal);
      calloc.free(digestParam);
      _macCtxFree(ctx);
      _macFree(mac);
      calloc.free(macName);
    }
  }
}

// ── SHA-256 (via EVP_Q_digest one-shot) ──────────────────────────────────────
class Sha256 {
  final DynamicLibrary _lib;
  late final int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      Pointer<IntPtr>) _qDigest;

  Sha256(this._lib) {
    _qDigest = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
            Pointer<Uint8>, IntPtr, Pointer<Uint8>, Pointer<IntPtr>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>,
            Pointer<Uint8>, int, Pointer<Uint8>, Pointer<IntPtr>)>(
        'EVP_Q_digest');
  }

  Uint8List hash(Uint8List data) => _digest('SHA256', data);

  /// SHA3-256 — used by X-Wing KEM combiner.
  Uint8List sha3_256(Uint8List data) => _digest('SHA3-256', data);

  Uint8List _digest(String algoName, Uint8List data) {
    final name = algoName.toNativeUtf8();
    final inBuf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final out = calloc<Uint8>(64); // SHA3-256 is 32B, give headroom
    final outLen = calloc<IntPtr>();
    try {
      if (data.isNotEmpty) inBuf.asTypedList(data.length).setAll(0, data);
      final rc =
          _qDigest(nullptr, name, nullptr, inBuf, data.length, out, outLen);
      if (rc <= 0) throw StateError('$algoName: EVP_Q_digest failed');
      return Uint8List.fromList(out.asTypedList(outLen.value));
    } finally {
      calloc.free(outLen);
      calloc.free(out);
      calloc.free(inBuf);
      calloc.free(name);
    }
  }
}

// ── X25519 — classical DH for the X-Wing hybrid KEM ──────────────────────────
//
// Used to compose hybrid PQ + classical defense-in-depth: even if ML-KEM is
// broken, the X25519 leg keeps the shared secret confidential (and vice versa).
// Per draft-connolly-cfrg-xwing-kem.

const int _evpPkeyX25519 = 1034; // NID_X25519

class X25519 {
  final DynamicLibrary _lib;

  late final Pointer<EVP_PKEY> Function(
      int, Pointer<Void>, Pointer<Uint8>, int) _newRawPrivateKey;
  late final Pointer<EVP_PKEY> Function(
      int, Pointer<Void>, Pointer<Uint8>, int) _newRawPublicKey;
  late final int Function(Pointer<EVP_PKEY>, Pointer<Uint8>, Pointer<IntPtr>)
      _getRawPublicKey;
  late final void Function(Pointer<EVP_PKEY>) _pkeyFree;
  late final Pointer<EVP_PKEY_CTX> Function(Pointer<EVP_PKEY>, Pointer<Void>)
      _ctxNew;
  late final void Function(Pointer<EVP_PKEY_CTX>) _ctxFree;
  late final int Function(Pointer<EVP_PKEY_CTX>) _deriveInit;
  late final int Function(Pointer<EVP_PKEY_CTX>, Pointer<EVP_PKEY>) _deriveSetPeer;
  late final int Function(Pointer<EVP_PKEY_CTX>, Pointer<Uint8>, Pointer<IntPtr>)
      _derive;

  X25519(this._lib) {
    _newRawPrivateKey = _lib.lookupFunction<
        Pointer<EVP_PKEY> Function(
            Int32, Pointer<Void>, Pointer<Uint8>, IntPtr),
        Pointer<EVP_PKEY> Function(
            int, Pointer<Void>, Pointer<Uint8>, int)>(
        'EVP_PKEY_new_raw_private_key');
    _newRawPublicKey = _lib.lookupFunction<
        Pointer<EVP_PKEY> Function(
            Int32, Pointer<Void>, Pointer<Uint8>, IntPtr),
        Pointer<EVP_PKEY> Function(
            int, Pointer<Void>, Pointer<Uint8>, int)>(
        'EVP_PKEY_new_raw_public_key');
    _getRawPublicKey = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_PKEY>, Pointer<Uint8>, Pointer<IntPtr>),
        int Function(Pointer<EVP_PKEY>, Pointer<Uint8>, Pointer<IntPtr>)>(
        'EVP_PKEY_get_raw_public_key');
    _pkeyFree = _lib.lookupFunction<Void Function(Pointer<EVP_PKEY>),
        void Function(Pointer<EVP_PKEY>)>('EVP_PKEY_free');
    _ctxNew = _lib.lookupFunction<
        Pointer<EVP_PKEY_CTX> Function(Pointer<EVP_PKEY>, Pointer<Void>),
        Pointer<EVP_PKEY_CTX> Function(Pointer<EVP_PKEY>, Pointer<Void>)>(
        'EVP_PKEY_CTX_new');
    _ctxFree = _lib.lookupFunction<Void Function(Pointer<EVP_PKEY_CTX>),
        void Function(Pointer<EVP_PKEY_CTX>)>('EVP_PKEY_CTX_free');
    _deriveInit = _lib.lookupFunction<Int32 Function(Pointer<EVP_PKEY_CTX>),
        int Function(Pointer<EVP_PKEY_CTX>)>('EVP_PKEY_derive_init');
    _deriveSetPeer = _lib.lookupFunction<
        Int32 Function(Pointer<EVP_PKEY_CTX>, Pointer<EVP_PKEY>),
        int Function(Pointer<EVP_PKEY_CTX>, Pointer<EVP_PKEY>)>(
        'EVP_PKEY_derive_set_peer');
    _derive = _lib.lookupFunction<
        Int32 Function(
            Pointer<EVP_PKEY_CTX>, Pointer<Uint8>, Pointer<IntPtr>),
        int Function(
            Pointer<EVP_PKEY_CTX>, Pointer<Uint8>, Pointer<IntPtr>)>(
        'EVP_PKEY_derive');
  }

  /// Returns (pk32, sk32) — both raw 32-byte X25519 values.
  (Uint8List pk, Uint8List sk) keygen(RandBytes rand) {
    final sk = rand.bytes(32);
    return (scalarMultBase(sk), sk);
  }

  /// X25519(sk, basepoint) — derive the public key for `sk`.
  Uint8List scalarMultBase(Uint8List sk) {
    final skBuf = calloc<Uint8>(32);
    skBuf.asTypedList(32).setAll(0, sk);
    final skPkey =
        _newRawPrivateKey(_evpPkeyX25519, nullptr, skBuf, 32);
    calloc.free(skBuf);
    if (skPkey.address == 0) {
      throw StateError('X25519: EVP_PKEY_new_raw_private_key failed');
    }
    try {
      final out = calloc<Uint8>(32);
      final outLen = calloc<IntPtr>()..value = 32;
      try {
        if (_getRawPublicKey(skPkey, out, outLen) <= 0) {
          throw StateError('X25519: EVP_PKEY_get_raw_public_key failed');
        }
        return Uint8List.fromList(out.asTypedList(32));
      } finally {
        calloc.free(outLen);
        calloc.free(out);
      }
    } finally {
      _pkeyFree(skPkey);
    }
  }

  /// X25519(sk, pk_peer) — the DH shared secret (32 B).
  Uint8List sharedSecret(Uint8List sk, Uint8List peerPk) {
    final skBuf = calloc<Uint8>(32);
    skBuf.asTypedList(32).setAll(0, sk);
    final skPkey =
        _newRawPrivateKey(_evpPkeyX25519, nullptr, skBuf, 32);
    calloc.free(skBuf);

    final pkBuf = calloc<Uint8>(32);
    pkBuf.asTypedList(32).setAll(0, peerPk);
    final peerPkey =
        _newRawPublicKey(_evpPkeyX25519, nullptr, pkBuf, 32);
    calloc.free(pkBuf);

    if (skPkey.address == 0 || peerPkey.address == 0) {
      throw StateError('X25519: raw-key import failed');
    }
    final ctx = _ctxNew(skPkey, nullptr);
    if (ctx.address == 0) {
      _pkeyFree(skPkey);
      _pkeyFree(peerPkey);
      throw StateError('X25519: EVP_PKEY_CTX_new failed');
    }
    try {
      if (_deriveInit(ctx) <= 0) {
        throw StateError('X25519: derive_init failed');
      }
      if (_deriveSetPeer(ctx, peerPkey) <= 0) {
        throw StateError('X25519: derive_set_peer failed');
      }
      final out = calloc<Uint8>(32);
      final outLen = calloc<IntPtr>()..value = 32;
      try {
        if (_derive(ctx, out, outLen) <= 0) {
          throw StateError('X25519: derive failed');
        }
        return Uint8List.fromList(out.asTypedList(outLen.value));
      } finally {
        calloc.free(outLen);
        calloc.free(out);
      }
    } finally {
      _ctxFree(ctx);
      _pkeyFree(skPkey);
      _pkeyFree(peerPkey);
    }
  }
}

// ── X-Wing KEM (X25519 + ML-KEM-768 hybrid) ──────────────────────────────────
//
// Implements draft-connolly-cfrg-xwing-kem-06. PQ + classical defense in depth:
// the AEAD shared secret is SHA3-256(LABEL || ss_ML || ss_X || ct_X || pk_X),
// so an attacker must break BOTH ML-KEM AND X25519 to recover ss.
//
// Sizes:  pk = 1216 B   sk = 2464 B   ct = 1120 B   ss = 32 B
//
// SK layout (flat bytes):  ML-KEM SK (2400) || X25519 sk (32) || X25519 pk (32)
// PK layout:               ML-KEM PK (1184) || X25519 pk (32)
// CT layout:               ML-KEM CT (1088) || X25519 ephemeral pk (32)
//
// Label per draft -06: ASCII bytes `\.//^\` (six bytes 0x5C 0x2E 0x2F 0x2F 0x5E 0x5C).

class XWingKem {
  static const int pkBytes = 1216;
  static const int skBytes = 2464;
  static const int ctBytes = 1120;
  static const int ssBytes = 32;

  static const int _mlKemPkLen = 1184;
  static const int _mlKemSkLen = 2400;
  static const int _mlKemCtLen = 1088;

  static final Uint8List _label =
      Uint8List.fromList(const [0x5C, 0x2E, 0x2F, 0x2F, 0x5E, 0x5C]);

  final OpenSslMlKem768 mlKem;
  final X25519 x25519;
  final Sha256 sha;
  final RandBytes rand;

  XWingKem(
      {required this.mlKem,
      required this.x25519,
      required this.sha,
      required this.rand});

  /// Returns (pkCombined, skCombined). The SK is opaque bytes — pass back to
  /// [decaps] verbatim.
  (Uint8List pk, Uint8List sk) keygen() {
    // ML-KEM leg
    final (pkM, kp) = mlKem.generateKeypair();
    final skM = mlKem.extractSecretKeyBytes(kp);
    mlKem.freeKey(kp);
    assert(pkM.length == _mlKemPkLen);
    assert(skM.length == _mlKemSkLen);

    // X25519 leg
    final (pkX, skX) = x25519.keygen(rand);

    final pk = Uint8List(pkBytes);
    pk.setAll(0, pkM);
    pk.setAll(_mlKemPkLen, pkX);

    final sk = Uint8List(skBytes);
    sk.setAll(0, skM);
    sk.setAll(_mlKemSkLen, skX);
    sk.setAll(_mlKemSkLen + 32, pkX);

    return (pk, sk);
  }

  /// Generate an X-Wing keypair deterministically from a 96-byte seed.
  /// seed[0:64] → ML-KEM-768 leg (64-byte seed for OpenSSL keygenFromSeed).
  /// seed[64:96] → X25519 leg (raw 32-byte private key).
  /// Returns (pk, sk) in the same layout as [keygen].
  (Uint8List pk, Uint8List sk) keygenFromSeed(Uint8List seed96) {
    assert(seed96.length == 96, 'X-Wing seed must be 96 bytes');

    // ML-KEM leg
    final (pkM, kpM) = mlKem.keygenFromSeed(Uint8List.sublistView(seed96, 0, 64));
    final skM = mlKem.extractSecretKeyBytes(kpM);
    mlKem.freeKey(kpM);
    assert(pkM.length == _mlKemPkLen);
    assert(skM.length == _mlKemSkLen);

    // X25519 leg — sk is the raw 32 bytes, pk derived via scalar mult
    final skX = Uint8List.fromList(seed96.sublist(64, 96));
    final pkX = x25519.scalarMultBase(skX);

    final pk = Uint8List(pkBytes);
    pk.setAll(0, pkM);
    pk.setAll(_mlKemPkLen, pkX);

    final sk = Uint8List(skBytes);
    sk.setAll(0, skM);
    sk.setAll(_mlKemSkLen, skX);
    sk.setAll(_mlKemSkLen + 32, pkX);

    return (pk, sk);
  }

  /// Encaps to a combined PK. Returns (ct, ss).
  (Uint8List ct, Uint8List ss) encaps(Uint8List pk) {
    if (pk.length != pkBytes) {
      throw ArgumentError('X-Wing pk must be $pkBytes bytes (got ${pk.length})');
    }
    final pkM = Uint8List.sublistView(pk, 0, _mlKemPkLen);
    final pkX = Uint8List.sublistView(pk, _mlKemPkLen);

    // ML-KEM encaps
    final pkeyM = mlKem.importPublicKey(Uint8List.fromList(pkM));
    Uint8List ctM, ssM;
    try {
      final (c, s) = mlKem.encapsulate(pkeyM);
      ctM = c;
      ssM = s;
    } finally {
      mlKem.freeKey(pkeyM);
    }

    // X25519 ephemeral keypair → ctX (ephemeral pk) + ssX (dh with recipient pkX)
    final (ctX, ekX) = x25519.keygen(rand);
    final ssX = x25519.sharedSecret(ekX, Uint8List.fromList(pkX));

    // ss = SHA3-256(LABEL || ssM || ssX || ctX || pkX)
    final ss = _combine(ssM, ssX, ctX, Uint8List.fromList(pkX));

    final ct = Uint8List(ctBytes);
    ct.setAll(0, ctM);
    ct.setAll(_mlKemCtLen, ctX);

    return (ct, ss);
  }

  /// Decaps. Returns ss.
  Uint8List decaps(Uint8List sk, Uint8List ct) {
    if (sk.length != skBytes) {
      throw ArgumentError('X-Wing sk must be $skBytes bytes (got ${sk.length})');
    }
    if (ct.length != ctBytes) {
      throw ArgumentError('X-Wing ct must be $ctBytes bytes (got ${ct.length})');
    }
    final skM = Uint8List.sublistView(sk, 0, _mlKemSkLen);
    final skX = Uint8List.sublistView(sk, _mlKemSkLen, _mlKemSkLen + 32);
    final pkX = Uint8List.sublistView(sk, _mlKemSkLen + 32);
    final ctM = Uint8List.sublistView(ct, 0, _mlKemCtLen);
    final ctX = Uint8List.sublistView(ct, _mlKemCtLen);

    // ML-KEM decaps
    final skPtr = mlKem.importSecretKey(Uint8List.fromList(skM));
    Uint8List ssM;
    try {
      ssM = mlKem.decapsulate(skPtr, Uint8List.fromList(ctM));
    } finally {
      mlKem.freeKey(skPtr);
    }

    // X25519 dh
    final ssX = x25519.sharedSecret(
        Uint8List.fromList(skX), Uint8List.fromList(ctX));

    return _combine(
        ssM, ssX, Uint8List.fromList(ctX), Uint8List.fromList(pkX));
  }

  Uint8List _combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    final buf = Uint8List(
        _label.length + ssM.length + ssX.length + ctX.length + pkX.length);
    var o = 0;
    buf.setAll(o, _label); o += _label.length;
    buf.setAll(o, ssM); o += ssM.length;
    buf.setAll(o, ssX); o += ssX.length;
    buf.setAll(o, ctX); o += ctX.length;
    buf.setAll(o, pkX);
    return sha.sha3_256(buf);
  }
}

// ── CSPRNG ───────────────────────────────────────────────────────────────────
class RandBytes {
  final DynamicLibrary _lib;
  late final int Function(Pointer<Uint8>, int) _randBytes;

  RandBytes(this._lib) {
    _randBytes = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Int32),
        int Function(Pointer<Uint8>, int)>('RAND_bytes');
  }

  Uint8List bytes(int n) {
    final buf = calloc<Uint8>(n);
    try {
      if (_randBytes(buf, n) <= 0) throw StateError('RAND_bytes failed');
      return Uint8List.fromList(buf.asTypedList(n));
    } finally {
      calloc.free(buf);
    }
  }
}

// ── HPKE in Dart on top of ML-KEM + HKDF + AES-GCM ───────────────────────────
//
// RFC 9180 base mode, ciphersuite: KEM = ML-KEM-768, KDF = HKDF-SHA256,
// AEAD = AES-256-GCM. We construct the key schedule manually so the demo
// reader can see exactly which bytes feed which primitive.

class Hpke {
  final XWingKem kem;
  final Hkdf hkdf;
  final AesGcm aesGcm;
  final RandBytes rand;

  Hpke({required this.kem, required this.hkdf, required this.aesGcm, required this.rand});

  /// HPKE KEM ciphertext (`enc`) size — exposed for assertions.
  int get encSize => XWingKem.ctBytes;

  static const String _kdfLabelKey = 'key';
  static const String _kdfLabelNonce = 'base_nonce';

  /// Seal: X-Wing encaps to recipient's hybrid PK, derive AEAD key+nonce,
  /// AES-GCM-seal the plaintext. Returns (enc, ct, tag) where enc is the
  /// X-Wing ciphertext (1120 B = ML-KEM CT 1088 || X25519 ephemeral PK 32).
  (Uint8List enc, Uint8List ct, Uint8List tag) seal(
      Uint8List recipientPk, Uint8List info, Uint8List aad, Uint8List plaintext) {
    final (enc, ss) = kem.encaps(recipientPk);
    final keyMaterial = hkdf.derive(
        Uint8List(0), ss, _concatLabel(_kdfLabelKey, info), 32);
    final nonce = hkdf.derive(
        Uint8List(0), ss, _concatLabel(_kdfLabelNonce, info), 12);
    final (ct, tag) = aesGcm.seal(keyMaterial, nonce, plaintext, aad: aad);
    return (enc, ct, tag);
  }

  /// Open: decaps with recipient's X-Wing SK bytes.
  Uint8List open(
      Uint8List recipientSk,
      Uint8List enc,
      Uint8List info,
      Uint8List aad,
      Uint8List ct,
      Uint8List tag) {
    final ss = kem.decaps(recipientSk, enc);
    final keyMaterial = hkdf.derive(
        Uint8List(0), ss, _concatLabel(_kdfLabelKey, info), 32);
    final nonce = hkdf.derive(
        Uint8List(0), ss, _concatLabel(_kdfLabelNonce, info), 12);
    return aesGcm.open(keyMaterial, nonce, ct, tag, aad: aad);
  }

  Uint8List _concatLabel(String label, Uint8List info) {
    final labelBytes = Uint8List.fromList(label.codeUnits);
    final out = Uint8List(labelBytes.length + 1 + info.length);
    out.setAll(0, labelBytes);
    out[labelBytes.length] = 0x00;
    out.setAll(labelBytes.length + 1, info);
    return out;
  }
}

// ── Bundle ───────────────────────────────────────────────────────────────────
/// Convenience holder for all primitive instances sharing one libcrypto.
class Crypto {
  final DynamicLibrary lib;
  final OpenSslMlKem768 mlKem;
  final MlDsa65 mlDsa;
  final X25519 x25519;
  final AesGcm aesGcm;
  final Hkdf hkdf;
  final HmacSha256 hmac;
  final Sha256 sha256;
  final RandBytes rand;
  late final XWingKem xwing;
  late final Hpke hpke;

  Crypto._(this.lib, this.mlKem, this.mlDsa, this.x25519, this.aesGcm,
      this.hkdf, this.hmac, this.sha256, this.rand) {
    xwing = XWingKem(mlKem: mlKem, x25519: x25519, sha: sha256, rand: rand);
    hpke = Hpke(kem: xwing, hkdf: hkdf, aesGcm: aesGcm, rand: rand);
  }

  factory Crypto.load([String path = defaultLibCryptoPath]) {
    final mlKem = OpenSslMlKem768.load(path);
    final lib = mlKem.lib;
    return Crypto._(lib, mlKem, MlDsa65(lib), X25519(lib), AesGcm(lib),
        Hkdf(lib), HmacSha256(lib), Sha256(lib), RandBytes(lib));
  }
}
