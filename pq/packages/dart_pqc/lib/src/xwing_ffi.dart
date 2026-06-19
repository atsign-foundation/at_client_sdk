import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'dart_pqc_base.dart';
import 'openssl_ffi_bindings.dart';

// X-Wing KEM — draft-connolly-cfrg-xwing-kem-06.
//
// PQ + classical defense-in-depth: attacker must break BOTH ML-KEM-768 AND
// X25519 to recover the shared secret.
//
// Key layout:
//   PK  (1216 B): ML-KEM-768 pk (1184) || X25519 pk (32)
//   SK  (2464 B): ML-KEM-768 raw priv (2400) || X25519 sk (32) || X25519 pk (32)
//   CT  (1120 B): ML-KEM-768 ct (1088) || X25519 ephemeral pk (32)
//   SS  (  32 B): SHA3-256(LABEL || ssM || ssX || ctX || pkX)
//   LABEL = 0x5C 0x2E 0x2F 0x2F 0x5E 0x5C  (ASCII "\.//<backslash>" per draft)

/// X-Wing KEM backed by OpenSSL 3 via Dart FFI.
///
/// Construct via [XWingFfi.fromLib].
final class XWingFfi implements XWingAlgorithm {
  static const int pkBytes = 1216;
  static const int skBytes = 2464;
  static const int ctBytes = 1120;
  static const int ssBytes = 32;

  static const int _mlKemPkLen = 1184;
  static const int _mlKemSkLen = 2400;
  static const int _mlKemCtLen = 1088;

  static final Uint8List _label =
      Uint8List.fromList([0x5C, 0x2E, 0x2F, 0x2F, 0x5E, 0x5C]);

  final DynamicLibrary _lib;
  final Random _rng = Random.secure();

  // ── ML-KEM-768 EVP operations ────────────────────────────────────────────
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
  late final EvpPkeyGetOctetStringParamDart _getOctetStringParam;
  late final EvpPkeyCtxSetParamsDart _setParams;

  // ── X25519 operations ─────────────────────────────────────────────────────
  late final EvpPkeyNewRawPrivateKeyDart _newRawPrivKey;
  late final EvpPkeyNewRawPublicKeyDart _newRawPubKey;
  late final EvpPkeyGetRawKeyDart _getRawPubKey;
  late final EvpPkeyDeriveInitDart _deriveInit;
  late final EvpPkeyDeriveSetPeerDart _deriveSetPeer;
  late final EvpPkeyDeriveDart _derive;

  // ── SHA3-256 ──────────────────────────────────────────────────────────────
  late final EvpQDigestDart _evpQDigest;

  XWingFfi.fromLib(this._lib) {
    _ctxNewFromName = _lib.lookupFunction<EvpPkeyCtxNewFromNameNative,
        EvpPkeyCtxNewFromNameDart>('EVP_PKEY_CTX_new_from_name');
    _ctxNew = _lib.lookupFunction<EvpPkeyCtxNewNative,
        EvpPkeyCtxNewDart>('EVP_PKEY_CTX_new');
    _ctxFree = _lib.lookupFunction<EvpPkeyCtxFreeNative,
        EvpPkeyCtxFreeDart>('EVP_PKEY_CTX_free');
    _pkeyFree = _lib.lookupFunction<EvpPkeyFreeNative,
        EvpPkeyFreeDart>('EVP_PKEY_free');
    _keygenInit = _lib.lookupFunction<EvpPkeyKeygenInitNative,
        EvpPkeyKeygenInitDart>('EVP_PKEY_keygen_init');
    _keygen = _lib.lookupFunction<EvpPkeyKeygenNative,
        EvpPkeyKeygenDart>('EVP_PKEY_keygen');
    _get1EncodedPubKey = _lib.lookupFunction<EvpPkeyGet1EncodedPublicKeyNative,
        EvpPkeyGet1EncodedPublicKeyDart>('EVP_PKEY_get1_encoded_public_key');
    _encapsInit = _lib.lookupFunction<EvpPkeyKemInitNative,
        EvpPkeyKemInitDart>('EVP_PKEY_encapsulate_init');
    _encapsulate = _lib.lookupFunction<EvpPkeyEncapsulateNative,
        EvpPkeyEncapsulateDart>('EVP_PKEY_encapsulate');
    _decapsInit = _lib.lookupFunction<EvpPkeyKemInitNative,
        EvpPkeyKemInitDart>('EVP_PKEY_decapsulate_init');
    _decapsulate = _lib.lookupFunction<EvpPkeyDecapsulateNative,
        EvpPkeyDecapsulateDart>('EVP_PKEY_decapsulate');
    _bldNew = _lib.lookupFunction<OsslParamBldNewNative,
        OsslParamBldNewDart>('OSSL_PARAM_BLD_new');
    _bldFree = _lib.lookupFunction<OsslParamBldFreeNative,
        OsslParamBldFreeDart>('OSSL_PARAM_BLD_free');
    _bldToParam = _lib.lookupFunction<OsslParamBldToParamNative,
        OsslParamBldToParamDart>('OSSL_PARAM_BLD_to_param');
    _bldPushOctet = _lib.lookupFunction<OsslParamBldPushOctetStringNative,
        OsslParamBldPushOctetStringDart>('OSSL_PARAM_BLD_push_octet_string');
    _paramFree = _lib.lookupFunction<OsslParamFreeNative,
        OsslParamFreeDart>('OSSL_PARAM_free');
    _fromdataInit = _lib.lookupFunction<EvpPkeyFromdataInitNative,
        EvpPkeyFromdataInitDart>('EVP_PKEY_fromdata_init');
    _fromdata = _lib.lookupFunction<EvpPkeyFromdataNative,
        EvpPkeyFromdataDart>('EVP_PKEY_fromdata');
    _cryptoFree = _lib.lookupFunction<CryptoFreeNative,
        CryptoFreeDart>('CRYPTO_free');
    _getOctetStringParam = _lib.lookupFunction<
        EvpPkeyGetOctetStringParamNative,
        EvpPkeyGetOctetStringParamDart>('EVP_PKEY_get_octet_string_param');
    _setParams = _lib.lookupFunction<EvpPkeyCtxSetParamsNative,
        EvpPkeyCtxSetParamsDart>('EVP_PKEY_CTX_set_params');
    _newRawPrivKey = _lib.lookupFunction<EvpPkeyNewRawPrivateKeyNative,
        EvpPkeyNewRawPrivateKeyDart>('EVP_PKEY_new_raw_private_key');
    _newRawPubKey = _lib.lookupFunction<EvpPkeyNewRawPublicKeyNative,
        EvpPkeyNewRawPublicKeyDart>('EVP_PKEY_new_raw_public_key');
    _getRawPubKey = _lib.lookupFunction<EvpPkeyGetRawKeyNative,
        EvpPkeyGetRawKeyDart>('EVP_PKEY_get_raw_public_key');
    _deriveInit = _lib.lookupFunction<EvpPkeyDeriveInitNative,
        EvpPkeyDeriveInitDart>('EVP_PKEY_derive_init');
    _deriveSetPeer = _lib.lookupFunction<EvpPkeyDeriveSetPeerNative,
        EvpPkeyDeriveSetPeerDart>('EVP_PKEY_derive_set_peer');
    _derive = _lib.lookupFunction<EvpPkeyDeriveNative,
        EvpPkeyDeriveDart>('EVP_PKEY_derive');
    _evpQDigest = _lib.lookupFunction<EvpQDigestNative,
        EvpQDigestDart>('EVP_Q_digest');
  }

  @override
  Future<PqcKeyPair> generateKeyPair([Uint8List? seed96]) async {
    if (seed96 != null) {
      assert(seed96.length == 96, 'X-Wing seed must be 96 bytes');
      return _keygenFromSeed(seed96);
    }
    return _keygen_();
  }

  @override
  Future<EncapsulationResult> encaps(Uint8List publicKey) async {
    if (publicKey.length != pkBytes) {
      throw ArgumentError(
          'X-Wing pk must be $pkBytes bytes (got ${publicKey.length})');
    }
    final pkM = Uint8List.sublistView(publicKey, 0, _mlKemPkLen);
    final pkX = Uint8List.sublistView(publicKey, _mlKemPkLen);

    // ML-KEM encaps
    final (ctM, ssM) = _mlKemEncaps(pkM);

    // X25519 ephemeral: ctX = ephemeral pk, ssX = DH(ekX, pkX)
    final skX = _randomBytes(32);
    final ctX = _x25519ScalarMultBase(skX);
    final ssX = _x25519DH(skX, pkX);

    final ss = _combine(ssM, ssX, ctX, pkX);

    final ct = Uint8List(ctBytes);
    ct.setAll(0, ctM);
    ct.setAll(_mlKemCtLen, ctX);

    return EncapsulationResult(ciphertext: ct, sharedSecret: ss);
  }

  @override
  Future<Uint8List> decaps(Uint8List secretKey, Uint8List ciphertext) async {
    if (secretKey.length != skBytes) {
      throw ArgumentError(
          'X-Wing sk must be $skBytes bytes (got ${secretKey.length})');
    }
    if (ciphertext.length != ctBytes) {
      throw ArgumentError(
          'X-Wing ct must be $ctBytes bytes (got ${ciphertext.length})');
    }

    final skM = Uint8List.sublistView(secretKey, 0, _mlKemSkLen);
    final skX = Uint8List.sublistView(secretKey, _mlKemSkLen, _mlKemSkLen + 32);
    final pkX = Uint8List.sublistView(secretKey, _mlKemSkLen + 32);
    final ctM = Uint8List.sublistView(ciphertext, 0, _mlKemCtLen);
    final ctX = Uint8List.sublistView(ciphertext, _mlKemCtLen);

    final ssM = _mlKemDecaps(skM, ctM);
    final ssX = _x25519DH(skX, ctX);

    return _combine(ssM, ssX, ctX, pkX);
  }

  // ── Key generation ─────────────────────────────────────────────────────────

  PqcKeyPair _keygen_() {
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final ctx = _ctxNewFromName(nullptr, algName, nullptr);
    calloc.free(algName);
    if (ctx == nullptr) throw StateError('XWing: ML-KEM CTX_new_from_name failed');

    try {
      if (_keygenInit(ctx) <= 0) throw StateError('XWing: ML-KEM keygen_init failed');
      final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
      try {
        if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('XWing: ML-KEM keygen failed');
        final pkey = pkeyPtr.value;
        try {
          final pkM = _extractEncodedPubKey(pkey);
          final skM = _extractOctetParam(pkey, 'priv');
          assert(pkM.length == _mlKemPkLen);
          assert(skM.length == _mlKemSkLen);

          final skX = _randomBytes(32);
          final pkX = _x25519ScalarMultBase(skX);

          return _buildKeyPair(pkM, skM, skX, pkX);
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

  PqcKeyPair _keygenFromSeed(Uint8List seed96) {
    final mlKemSeed = Uint8List.sublistView(seed96, 0, 64);
    final skX = Uint8List.sublistView(seed96, 64, 96);

    // ML-KEM deterministic keygen via EVP_PKEY_CTX_set_params("seed")
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final seedName = 'seed'.toNativeUtf8();
    final seedBuf = calloc<Uint8>(64);
    seedBuf.asTypedList(64).setAll(0, mlKemSeed);

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();

    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('XWing: BLD_new failed');
      if (_bldPushOctet(bld, seedName, seedBuf, 64) <= 0) {
        _bldFree(bld);
        throw StateError('XWing: bld push seed failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('XWing: bld to_param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('XWing: CTX_new_from_name failed');
      if (_keygenInit(ctx) <= 0) throw StateError('XWing: keygen_init failed');
      if (_setParams(ctx, params) <= 0) throw StateError('XWing: set_params (seed) failed');
      if (_keygen(ctx, pkeyPtr) <= 0) throw StateError('XWing: keygen failed');

      final pkey = pkeyPtr.value;
      try {
        final pkM = _extractEncodedPubKey(pkey);
        final skMBytes = _extractOctetParam(pkey, 'priv');
        final pkX = _x25519ScalarMultBase(skX);
        return _buildKeyPair(pkM, skMBytes, skX, pkX);
      } finally {
        _pkeyFree(pkey);
      }
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      calloc.free(seedBuf);
      calloc.free(seedName);
      calloc.free(algName);
      calloc.free(pkeyPtr);
    }
  }

  static PqcKeyPair _buildKeyPair(
      Uint8List pkM, Uint8List skM, Uint8List skX, Uint8List pkX) {
    final pk = Uint8List(pkBytes);
    pk.setAll(0, pkM);
    pk.setAll(_mlKemPkLen, pkX);

    final sk = Uint8List(skBytes);
    sk.setAll(0, skM);
    sk.setAll(_mlKemSkLen, skX);
    sk.setAll(_mlKemSkLen + 32, pkX);

    return PqcKeyPair(publicKey: pk, secretKey: sk);
  }

  // ── ML-KEM helpers ─────────────────────────────────────────────────────────

  (Uint8List ct, Uint8List ss) _mlKemEncaps(Uint8List pkBytes_) {
    final pkey = _importMlKemPk(pkBytes_);
    try {
      final ctx = _ctxNew(pkey, nullptr);
      if (ctx == nullptr) throw StateError('XWing: ML-KEM EVP_PKEY_CTX_new failed');
      try {
        if (_encapsInit(ctx, nullptr) <= 0) {
          throw StateError('XWing: ML-KEM encapsulate_init failed');
        }
        final ctLen = calloc<IntPtr>();
        final ssLen = calloc<IntPtr>();
        try {
          if (_encapsulate(ctx, nullptr, ctLen, nullptr, ssLen) <= 0) {
            throw StateError('XWing: ML-KEM encapsulate size query failed');
          }
          final ctBuf = calloc<Uint8>(ctLen.value);
          final ssBuf = calloc<Uint8>(ssLen.value);
          try {
            if (_encapsulate(ctx, ctBuf, ctLen, ssBuf, ssLen) <= 0) {
              throw StateError('XWing: ML-KEM encapsulate failed');
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
    } finally {
      _pkeyFree(pkey);
    }
  }

  Uint8List _mlKemDecaps(Uint8List skBytes_, Uint8List ctBytes_) {
    final pkey = _importMlKemSk(skBytes_);
    try {
      final ctx = _ctxNew(pkey, nullptr);
      if (ctx == nullptr) throw StateError('XWing: ML-KEM EVP_PKEY_CTX_new failed');
      try {
        if (_decapsInit(ctx, nullptr) <= 0) {
          throw StateError('XWing: ML-KEM decapsulate_init failed');
        }
        final ssLen = calloc<IntPtr>();
        final ctBuf = calloc<Uint8>(ctBytes_.length);
        ctBuf.asTypedList(ctBytes_.length).setAll(0, ctBytes_);
        try {
          if (_decapsulate(ctx, nullptr, ssLen, ctBuf, ctBytes_.length) <= 0) {
            throw StateError('XWing: ML-KEM decapsulate size query failed');
          }
          final ssBuf = calloc<Uint8>(ssLen.value);
          try {
            if (_decapsulate(ctx, ssBuf, ssLen, ctBuf, ctBytes_.length) <= 0) {
              throw StateError('XWing: ML-KEM decapsulate failed');
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
    } finally {
      _pkeyFree(pkey);
    }
  }

  Pointer<EVP_PKEY> _importMlKemPk(Uint8List pkBytes_) {
    return _importMlKemKey(pkBytes_, 'pub', evpPkeyPublicKey);
  }

  Pointer<EVP_PKEY> _importMlKemSk(Uint8List skBytes_) {
    return _importMlKemKey(skBytes_, 'priv', evpPkeyKeypair);
  }

  Pointer<EVP_PKEY> _importMlKemKey(
      Uint8List keyBytes, String paramName, int selection) {
    final algName = 'ML-KEM-768'.toNativeUtf8();
    final pname = paramName.toNativeUtf8();
    final keyBuf = calloc<Uint8>(keyBytes.length);
    keyBuf.asTypedList(keyBytes.length).setAll(0, keyBytes);

    Pointer<OSSL_PARAM>? params;
    Pointer<EVP_PKEY_CTX>? ctx;
    final pkeyPtr = calloc<Pointer<EVP_PKEY>>();
    try {
      final bld = _bldNew();
      if (bld == nullptr) throw StateError('XWing: BLD_new failed');
      if (_bldPushOctet(bld, pname, keyBuf, keyBytes.length) <= 0) {
        _bldFree(bld);
        throw StateError('XWing: bld push octet failed');
      }
      params = _bldToParam(bld);
      _bldFree(bld);
      if (params == nullptr) throw StateError('XWing: bld to_param failed');

      ctx = _ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) throw StateError('XWing: CTX_new_from_name failed');
      if (_fromdataInit(ctx) <= 0) throw StateError('XWing: fromdata_init failed');
      if (_fromdata(ctx, pkeyPtr, selection, params) <= 0) {
        throw StateError('XWing: fromdata failed');
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

  Uint8List _extractEncodedPubKey(Pointer<EVP_PKEY> pkey) {
    final ppub = calloc<Pointer<Uint8>>();
    try {
      final len = _get1EncodedPubKey(pkey, ppub);
      if (len <= 0) throw StateError('XWing: get1_encoded_public_key failed');
      final bytes = Uint8List.fromList(ppub.value.asTypedList(len));
      _cryptoFree(ppub.value.cast(), nullptr, 0);
      return bytes;
    } finally {
      calloc.free(ppub);
    }
  }

  Uint8List _extractOctetParam(Pointer<EVP_PKEY> pkey, String name) {
    final nameBuf = name.toNativeUtf8();
    final outLen = calloc<IntPtr>();
    try {
      if (_getOctetStringParam(pkey, nameBuf, nullptr, 0, outLen) <= 0) {
        throw StateError('XWing: get_octet_string_param "$name" size query failed');
      }
      final buf = calloc<Uint8>(outLen.value);
      try {
        if (_getOctetStringParam(pkey, nameBuf, buf, outLen.value, outLen) <= 0) {
          throw StateError('XWing: get_octet_string_param "$name" failed');
        }
        return Uint8List.fromList(buf.asTypedList(outLen.value));
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(outLen);
      calloc.free(nameBuf);
    }
  }

  // ── X25519 helpers ─────────────────────────────────────────────────────────

  Uint8List _x25519ScalarMultBase(Uint8List sk) {
    final skBuf = calloc<Uint8>(32);
    skBuf.asTypedList(32).setAll(0, sk);
    final pkey = _newRawPrivKey(nidX25519, nullptr, skBuf, 32);
    calloc.free(skBuf);
    if (pkey == nullptr) throw StateError('XWing: X25519 new_raw_private_key failed');
    try {
      final out = calloc<Uint8>(32);
      final outLen = calloc<IntPtr>()..value = 32;
      try {
        if (_getRawPubKey(pkey, out, outLen) <= 0) {
          throw StateError('XWing: X25519 get_raw_public_key failed');
        }
        return Uint8List.fromList(out.asTypedList(32));
      } finally {
        calloc.free(outLen);
        calloc.free(out);
      }
    } finally {
      _pkeyFree(pkey);
    }
  }

  Uint8List _x25519DH(Uint8List sk, Uint8List peerPk) {
    final skBuf = calloc<Uint8>(32);
    skBuf.asTypedList(32).setAll(0, sk);
    final myKey = _newRawPrivKey(nidX25519, nullptr, skBuf, 32);
    calloc.free(skBuf);

    final pkBuf = calloc<Uint8>(32);
    pkBuf.asTypedList(32).setAll(0, peerPk);
    final peerKey = _newRawPubKey(nidX25519, nullptr, pkBuf, 32);
    calloc.free(pkBuf);

    if (myKey == nullptr || peerKey == nullptr) {
      throw StateError('XWing: X25519 key import failed');
    }

    final ctx = _ctxNew(myKey, nullptr);
    if (ctx == nullptr) throw StateError('XWing: X25519 CTX_new failed');
    try {
      if (_deriveInit(ctx) <= 0) throw StateError('XWing: X25519 derive_init failed');
      if (_deriveSetPeer(ctx, peerKey) <= 0) {
        throw StateError('XWing: X25519 derive_set_peer failed');
      }
      final out = calloc<Uint8>(32);
      final outLen = calloc<IntPtr>()..value = 32;
      try {
        if (_derive(ctx, out, outLen) <= 0) {
          throw StateError('XWing: X25519 derive failed');
        }
        return Uint8List.fromList(out.asTypedList(outLen.value));
      } finally {
        calloc.free(outLen);
        calloc.free(out);
      }
    } finally {
      _ctxFree(ctx);
      _pkeyFree(myKey);
      _pkeyFree(peerKey);
    }
  }

  // ── SHA3-256 combiner ──────────────────────────────────────────────────────

  Uint8List _combine(
      Uint8List ssM, Uint8List ssX, Uint8List ctX, Uint8List pkX) {
    final buf = Uint8List(
        _label.length + ssM.length + ssX.length + ctX.length + pkX.length);
    var o = 0;
    buf.setAll(o, _label);
    o += _label.length;
    buf.setAll(o, ssM);
    o += ssM.length;
    buf.setAll(o, ssX);
    o += ssX.length;
    buf.setAll(o, ctX);
    o += ctX.length;
    buf.setAll(o, pkX);
    return _sha3_256(buf);
  }

  Uint8List _sha3_256(Uint8List data) {
    final algName = 'SHA3-256'.toNativeUtf8();
    final inBuf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final out = calloc<Uint8>(32);
    final outLen = calloc<IntPtr>();
    try {
      if (data.isNotEmpty) inBuf.asTypedList(data.length).setAll(0, data);
      final rc = _evpQDigest(
          nullptr, algName, nullptr, inBuf, data.length, out, outLen);
      if (rc <= 0) throw StateError('XWing: SHA3-256 EVP_Q_digest failed');
      return Uint8List.fromList(out.asTypedList(outLen.value));
    } finally {
      calloc.free(outLen);
      calloc.free(out);
      calloc.free(inBuf);
      calloc.free(algName);
    }
  }

  // ── CSPRNG ─────────────────────────────────────────────────────────────────

  Uint8List _randomBytes(int n) {
    final bytes = Uint8List(n);
    for (int i = 0; i < n; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }
}
