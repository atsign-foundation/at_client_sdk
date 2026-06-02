import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dart_pqc_base.dart';
import 'openssl_ffi_bindings.dart';

/// X25519 ECDH expressed as a KEM (ephemeral sender), backed by OpenSSL 3 FFI.
///
/// Follows the same ephemeral-sender pattern as [X25519PureDart]:
///
///   Alice:  generateKeyPair() → (pk_A, sk_A)
///   Bob:    encapsulate(pk_A)  → (ct = pk_B_ephemeral, ss = DH(sk_B, pk_A))
///   Alice:  decapsulate(sk_A, ct=pk_B) → ss = DH(sk_A, pk_B)
///
/// Construct via [X25519Ffi.fromLib].
final class X25519Ffi implements KemAlgorithm {
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

  X25519Ffi.fromLib(this._lib) {
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

  @override
  String get name => 'X25519';

  @override
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed]) async {
    // Seed not supported by OpenSSL EVP X25519 API; ignored.
    final Pointer<Utf8> algName = 'X25519'.toNativeUtf8();
    final Pointer<EVP_PKEY_CTX> ctx =
        _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('EVP_PKEY_CTX_new_from_name failed');

    try {
      if (_keygenInit(ctx) <= 0) throw StateError('EVP_PKEY_keygen_init failed');
      final Pointer<Pointer<EVP_PKEY>> pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('EVP_PKEY_keygen failed');
        final Pointer<EVP_PKEY> pkey = pkeyPtr.value;
        try {
          final Uint8List pubBytes = _extractRawPublicKey(pkey);
          final Uint8List privBytes = _extractRawPrivateKey(pkey);
          return PqcKeyPair(publicKey: pubBytes, secretKey: privBytes);
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
  Future<EncapsulationResult> encapsulate(Uint8List publicKey) async {
    // Generate ephemeral sender key pair.
    final Pointer<Utf8> algName = 'X25519'.toNativeUtf8();
    final Pointer<EVP_PKEY_CTX> keygenCtx =
        _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (keygenCtx == nullptr) throw StateError('EVP_PKEY_CTX_new_from_name failed');

    Pointer<EVP_PKEY>? ephemeralKey;
    try {
      if (_keygenInit(keygenCtx) <= 0) {
        throw StateError('EVP_PKEY_keygen_init failed');
      }
      final Pointer<Pointer<EVP_PKEY>> ephPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(keygenCtx, ephPtr) <= 0) {
          throw StateError('EVP_PKEY_keygen failed');
        }
        ephemeralKey = ephPtr.value;
      } finally {
        calloc.free(ephPtr);
      }
    } finally {
      _ctxFree(keygenCtx);
    }

    try {
      final Uint8List ephPubBytes = _extractRawPublicKey(ephemeralKey!);

      // Import recipient's public key.
      final Pointer<Uint8> recipBuf = calloc<Uint8>(publicKey.length);
      recipBuf.asTypedList(publicKey.length).setAll(0, publicKey);
      final Pointer<EVP_PKEY> recipKey =
          _newRawPublicKey(nidX25519, nullptr, recipBuf, publicKey.length);
      calloc.free(recipBuf);
      if (recipKey == nullptr) throw StateError('EVP_PKEY_new_raw_public_key failed');

      try {
        final Uint8List ss = _ecdh(ephemeralKey!, recipKey);
        return EncapsulationResult(ciphertext: ephPubBytes, sharedSecret: ss);
      } finally {
        _pkeyFree(recipKey);
      }
    } finally {
      if (ephemeralKey != null) _pkeyFree(ephemeralKey);
    }
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List secretKey, Uint8List ciphertext) async {
    // Reconstruct recipient key pair from raw private key bytes.
    final Pointer<Uint8> privBuf = calloc<Uint8>(secretKey.length);
    privBuf.asTypedList(secretKey.length).setAll(0, secretKey);
    final Pointer<EVP_PKEY> recipKey =
        _newRawPrivateKey(nidX25519, nullptr, privBuf, secretKey.length);
    calloc.free(privBuf);
    if (recipKey == nullptr) throw StateError('EVP_PKEY_new_raw_private_key failed');

    try {
      // The ciphertext IS the sender's ephemeral public key.
      final Pointer<Uint8> senderBuf = calloc<Uint8>(ciphertext.length);
      senderBuf.asTypedList(ciphertext.length).setAll(0, ciphertext);
      final Pointer<EVP_PKEY> senderKey =
          _newRawPublicKey(nidX25519, nullptr, senderBuf, ciphertext.length);
      calloc.free(senderBuf);
      if (senderKey == nullptr) throw StateError('EVP_PKEY_new_raw_public_key failed');

      try {
        return _ecdh(recipKey, senderKey);
      } finally {
        _pkeyFree(senderKey);
      }
    } finally {
      _pkeyFree(recipKey);
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
      if (_deriveInit(ctx) <= 0) throw StateError('EVP_PKEY_derive_init failed');
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
