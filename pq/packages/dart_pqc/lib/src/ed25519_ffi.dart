import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dart_pqc_base.dart';
import 'openssl_ffi_bindings.dart';

/// Ed25519 signing — OpenSSL 3 FFI.
///
/// Uses one-shot EVP_DigestSign / EVP_DigestVerify (OpenSSL 3 API).
/// Construct via [Ed25519Ffi.fromLib].
final class Ed25519Ffi implements Ed25519Algorithm {
  final DynamicLibrary _lib;

  late final EvpPkeyCtxNewFromNameDart _ctxNewFromName;
  late final EvpPkeyCtxFreeDart _ctxFree;
  late final EvpPkeyFreeDart _pkeyFree;
  late final EvpPkeyKeygenInitDart _keygenInit;
  late final EvpPkeyKeygenDart _keygen;
  late final EvpPkeyGetRawKeyDart _getRawPublicKey;
  late final EvpPkeyGetRawKeyDart _getRawPrivateKey;
  late final EvpPkeyNewRawPrivateKeyDart _newRawPrivateKey;
  late final EvpPkeyNewRawPublicKeyDart _newRawPublicKey;
  late final EvpMdCtxNewDart _mdCtxNew;
  late final EvpMdCtxFreeDart _mdCtxFree;
  late final EvpDigestSignInitDart _digestSignInit;
  late final EvpDigestSignDart _digestSign;
  late final EvpDigestVerifyInitDart _digestVerifyInit;
  late final EvpDigestVerifyDart _digestVerify;

  Ed25519Ffi.fromLib(this._lib) {
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
    _newRawPrivateKey = _lib.lookupFunction<EvpPkeyNewRawPrivateKeyNative,
        EvpPkeyNewRawPrivateKeyDart>('EVP_PKEY_new_raw_private_key');
    _newRawPublicKey = _lib.lookupFunction<EvpPkeyNewRawPublicKeyNative,
        EvpPkeyNewRawPublicKeyDart>('EVP_PKEY_new_raw_public_key');
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
    _digestVerify =
        _lib.lookupFunction<EvpDigestVerifyNative, EvpDigestVerifyDart>(
            'EVP_DigestVerify');
  }

  /// Generate a fresh Ed25519 key pair.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair() async {
    final Pointer<Utf8> algName = 'ED25519'.toNativeUtf8();
    final Pointer<EVP_PKEY_CTX> ctx = _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new_from_name failed');

    try {
      if (_keygenInit(ctx) <= 0) throw StateError('EVP_PKEY_keygen_init failed');
      final Pointer<Pointer<EVP_PKEY>> pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('EVP_PKEY_keygen failed');
        final Pointer<EVP_PKEY> pkey = pkeyPtr.value;
        try {
          return (
            publicKey: _extractRawPublicKey(pkey),
            privateKey: _extractRawPrivateKey(pkey),
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

  /// Sign [message] with [privateKey].
  ///
  /// Returns a 64-byte signature.
  Future<Uint8List> sign(Uint8List privateKey, Uint8List message) async {
    final Pointer<Uint8> privBuf = calloc<Uint8>(privateKey.length);
    privBuf.asTypedList(privateKey.length).setAll(0, privateKey);
    final Pointer<EVP_PKEY> pkey =
        _newRawPrivateKey(nidEd25519, nullptr, privBuf, privateKey.length);
    calloc.free(privBuf);
    if (pkey == nullptr) throw StateError('EVP_PKEY_new_raw_private_key failed');

    try {
      final Pointer<Void> mdCtx = _mdCtxNew();
      if (mdCtx == nullptr) throw StateError('EVP_MD_CTX_new failed');
      try {
        if (_digestSignInit(mdCtx, nullptr, nullptr, nullptr, pkey) <= 0) {
          throw StateError('EVP_DigestSignInit failed');
        }

        // Ed25519 signatures are always exactly 64 bytes — skip the size query
        // to avoid calling EVP_DigestSign twice on the same context, which is
        // not safe across all OpenSSL versions.
        const int ed25519SigLen = 64;
        final Pointer<Uint8> msgBuf = calloc<Uint8>(message.length);
        final Pointer<Uint8> sigBuf = calloc<Uint8>(ed25519SigLen);
        final Pointer<IntPtr> sigLen = calloc<IntPtr>()..value = ed25519SigLen;
        msgBuf.asTypedList(message.length).setAll(0, message);
        try {
          if (_digestSign(mdCtx, sigBuf, sigLen, msgBuf, message.length) <= 0) {
            throw StateError('EVP_DigestSign failed');
          }
          return Uint8List.fromList(sigBuf.asTypedList(sigLen.value));
        } finally {
          calloc.free(msgBuf);
          calloc.free(sigBuf);
          calloc.free(sigLen);
        }
      } finally {
        _mdCtxFree(mdCtx);
      }
    } finally {
      _pkeyFree(pkey);
    }
  }

  /// Verify [signature] over [message] with [publicKey].
  ///
  /// Returns `true` if the signature is valid.
  Future<bool> verify(
      Uint8List publicKey, Uint8List message, Uint8List signature) async {
    final Pointer<Uint8> pubBuf = calloc<Uint8>(publicKey.length);
    pubBuf.asTypedList(publicKey.length).setAll(0, publicKey);
    final Pointer<EVP_PKEY> pkey =
        _newRawPublicKey(nidEd25519, nullptr, pubBuf, publicKey.length);
    calloc.free(pubBuf);
    if (pkey == nullptr) throw StateError('EVP_PKEY_new_raw_public_key failed');

    try {
      final Pointer<Void> mdCtx = _mdCtxNew();
      if (mdCtx == nullptr) throw StateError('EVP_MD_CTX_new failed');
      try {
        if (_digestVerifyInit(mdCtx, nullptr, nullptr, nullptr, pkey) <= 0) {
          throw StateError('EVP_DigestVerifyInit failed');
        }

        final Pointer<Uint8> msgBuf = calloc<Uint8>(message.length);
        final Pointer<Uint8> sigBuf = calloc<Uint8>(signature.length);
        msgBuf.asTypedList(message.length).setAll(0, message);
        sigBuf.asTypedList(signature.length).setAll(0, signature);
        try {
          final int result = _digestVerify(
              mdCtx, sigBuf, signature.length, msgBuf, message.length);
          return result == 1;
        } finally {
          calloc.free(msgBuf);
          calloc.free(sigBuf);
        }
      } finally {
        _mdCtxFree(mdCtx);
      }
    } finally {
      _pkeyFree(pkey);
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

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
}
