import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart';
import 'package:ffi/ffi.dart';

/// X25519 Diffie–Hellman key agreement backed by OpenSSL 3 via Dart FFI.
///
/// The caller loads libcrypto (e.g. via [tryLoadLibCrypto]) and passes the
/// resulting [DynamicLibrary] in. at_chops does no auto-resolution —
/// consumers decide their own fallback strategy.
final class X25519FfiAlgo implements AtKeyAgreementAlgorithm {
  final DynamicLibrary _lib;

  late final EvpPkeyCtxNewFromNameDart _ctxNewFromName;
  late final EvpPkeyCtxNewDart _ctxNew;
  late final EvpPkeyCtxFreeDart _ctxFree;
  late final EvpPkeyFreeDart _pkeyFree;
  late final EvpPkeyKeygenInitDart _keygenInit;
  late final EvpPkeyKeygenDart _keygen;
  late final EvpPkeyGetRawKeyDart _getRawPublicKey;
  late final EvpPkeyGetRawKeyDart _getRawPrivateKey;
  late final EvpPkeyNewRawPrivateKeyDart _newRawPrivateKey;
  late final EvpPkeyNewRawPublicKeyDart _newRawPublicKey;
  late final EvpPkeyDeriveInitDart _deriveInit;
  late final EvpPkeyDeriveSetPeerDart _deriveSetPeer;
  late final EvpPkeyDeriveDart _derive;

  X25519FfiAlgo.fromLib(this._lib) {
    _ctxNewFromName = _lib.lookupFunction<EvpPkeyCtxNewFromNameNative,
        EvpPkeyCtxNewFromNameDart>('EVP_PKEY_CTX_new_from_name');
    _ctxNew = _lib.lookupFunction<EvpPkeyCtxNewNative, EvpPkeyCtxNewDart>(
        'EVP_PKEY_CTX_new');
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
    _deriveInit = _lib.lookupFunction<EvpPkeyDeriveInitNative,
        EvpPkeyDeriveInitDart>('EVP_PKEY_derive_init');
    _deriveSetPeer = _lib.lookupFunction<EvpPkeyDeriveSetPeerNative,
        EvpPkeyDeriveSetPeerDart>('EVP_PKEY_derive_set_peer');
    _derive = _lib.lookupFunction<EvpPkeyDeriveNative, EvpPkeyDeriveDart>(
        'EVP_PKEY_derive');
  }

  /// Generate a fresh X25519 key pair via OpenSSL.
  ///
  /// Returns `(publicKey: 32 bytes, privateKey: 32 bytes)`.
  Future<({Uint8List publicKey, Uint8List privateKey})>
      generateKeyPair() async {
    final Pointer<Utf8> algName = 'X25519'.toNativeUtf8();
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

  @override
  Future<Uint8List> dh(Uint8List privateKey, Uint8List peerPublicKey) async {
    final Pointer<Uint8> privBuf = calloc<Uint8>(privateKey.length);
    privBuf.asTypedList(privateKey.length).setAll(0, privateKey);
    final Pointer<EVP_PKEY> myKey =
        _newRawPrivateKey(nidX25519, nullptr, privBuf, privateKey.length);
    calloc.free(privBuf);
    if (myKey == nullptr) {
      throw StateError('EVP_PKEY_new_raw_private_key failed');
    }

    try {
      final Pointer<Uint8> peerBuf = calloc<Uint8>(peerPublicKey.length);
      peerBuf.asTypedList(peerPublicKey.length).setAll(0, peerPublicKey);
      final Pointer<EVP_PKEY> peerKey = _newRawPublicKey(
          nidX25519, nullptr, peerBuf, peerPublicKey.length);
      calloc.free(peerBuf);
      if (peerKey == nullptr) {
        throw StateError('EVP_PKEY_new_raw_public_key failed');
      }

      try {
        return _ecdh(myKey, peerKey);
      } finally {
        _pkeyFree(peerKey);
      }
    } finally {
      _pkeyFree(myKey);
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

  Uint8List _ecdh(Pointer<EVP_PKEY> myKey, Pointer<EVP_PKEY> peerKey) {
    final Pointer<EVP_PKEY_CTX> ctx = _ctxNew(myKey, nullptr);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new failed');
    try {
      if (_deriveInit(ctx) <= 0) {
        throw StateError('EVP_PKEY_derive_init failed');
      }
      if (_deriveSetPeer(ctx, peerKey) <= 0) {
        throw StateError('EVP_PKEY_derive_set_peer failed');
      }
      final Pointer<IntPtr> lenPtr = calloc<IntPtr>();
      try {
        if (_derive(ctx, nullptr, lenPtr) <= 0) {
          throw StateError('EVP_PKEY_derive (size) failed');
        }
        final Pointer<Uint8> ssBuf = calloc<Uint8>(lenPtr.value);
        try {
          if (_derive(ctx, ssBuf, lenPtr) <= 0) {
            throw StateError('EVP_PKEY_derive failed');
          }
          return Uint8List.fromList(ssBuf.asTypedList(lenPtr.value));
        } finally {
          calloc.free(ssBuf);
        }
      } finally {
        calloc.free(lenPtr);
      }
    } finally {
      _ctxFree(ctx);
    }
  }
}
