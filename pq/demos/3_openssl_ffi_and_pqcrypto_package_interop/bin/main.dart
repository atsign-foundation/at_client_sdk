import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:pqcrypto/pqcrypto.dart';

// ── OpenSSL EVP opaque types ──────────────────────────────────────────────────
final class EVP_PKEY extends Opaque {}
final class EVP_PKEY_CTX extends Opaque {}
final class OSSL_PARAM extends Opaque {}
final class OSSL_PARAM_BLD extends Opaque {}

// ── FFI typedefs ─────────────────────────────────────────────────────────────

// EVP_PKEY_CTX_new_from_name(NULL, "ML-KEM-768", NULL)
typedef EvpPkeyCtxNewFromNameNative = Pointer<EVP_PKEY_CTX> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>);
typedef EvpPkeyCtxNewFromNameDart = Pointer<EVP_PKEY_CTX> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>);

// EVP_PKEY_CTX_new(EVP_PKEY*, ENGINE*)  — for decaps ctx from existing key
typedef EvpPkeyCtxNewNative = Pointer<EVP_PKEY_CTX> Function(
    Pointer<EVP_PKEY>, Pointer<Void>);
typedef EvpPkeyCtxNewDart = Pointer<EVP_PKEY_CTX> Function(
    Pointer<EVP_PKEY>, Pointer<Void>);

typedef EvpPkeyCtxFreeNative = Void Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyCtxFreeDart = void Function(Pointer<EVP_PKEY_CTX>);

typedef EvpPkeyFreeNative = Void Function(Pointer<EVP_PKEY>);
typedef EvpPkeyFreeDart = void Function(Pointer<EVP_PKEY>);

// EVP_PKEY_keygen_init(ctx)
typedef EvpPkeyKeygenInitNative = Int32 Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyKeygenInitDart = int Function(Pointer<EVP_PKEY_CTX>);

// EVP_PKEY_encapsulate_init(ctx, params[]) / EVP_PKEY_decapsulate_init(ctx, params[])
typedef EvpPkeyKemInitNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Void>);
typedef EvpPkeyKemInitDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Void>);

// EVP_PKEY_fromdata_init(ctx)
typedef EvpPkeyFromdataInitNative = Int32 Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyFromdataInitDart = int Function(Pointer<EVP_PKEY_CTX>);

// EVP_PKEY_keygen(ctx, EVP_PKEY**)
typedef EvpPkeyKeygenNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>);
typedef EvpPkeyKeygenDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Pointer<EVP_PKEY>>);

// EVP_PKEY_get1_encoded_public_key(pkey, unsigned char**) -> size_t
typedef EvpPkeyGet1EncodedPublicKeyNative = IntPtr Function(
    Pointer<EVP_PKEY>, Pointer<Pointer<Uint8>>);
typedef EvpPkeyGet1EncodedPublicKeyDart = int Function(
    Pointer<EVP_PKEY>, Pointer<Pointer<Uint8>>);

// EVP_PKEY_encapsulate(ctx, wrappedkey*, wrappedkeylen*, genkey*, genkeylen*)
typedef EvpPkeyEncapsulateNative = Int32 Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, Pointer<IntPtr>);
typedef EvpPkeyEncapsulateDart = int Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, Pointer<IntPtr>);

// EVP_PKEY_decapsulate(ctx, unwrapped*, unwrappedlen*, wrapped*, wrappedlen)
typedef EvpPkeyDecapsulateNative = Int32 Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, IntPtr);
typedef EvpPkeyDecapsulateDart = int Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, int);

// OSSL_PARAM_BLD_new / free / to_param
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

// EVP_PKEY_fromdata_init / EVP_PKEY_fromdata  (defined above, no duplicate needed)

typedef EvpPkeyFromdataNative = Int32 Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Pointer<EVP_PKEY>>, Int32, Pointer<OSSL_PARAM>);
typedef EvpPkeyFromdataDart = int Function(Pointer<EVP_PKEY_CTX>,
    Pointer<Pointer<EVP_PKEY>>, int, Pointer<OSSL_PARAM>);

// CRYPTO_free
typedef CryptoFreeNative = Void Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef CryptoFreeDart = void Function(Pointer<Void>, Pointer<Utf8>, int);

// ── OpenSSL selection constants ───────────────────────────────────────────────
// OSSL_KEYMGMT_SELECT_ALL_PARAMETERS = 0x04 | 0x80 = 0x84
// EVP_PKEY_PUBLIC_KEY = ALL_PARAMETERS | PUBLIC_KEY(0x02) = 0x86
// EVP_PKEY_KEYPAIR    = ALL_PARAMETERS | PUBLIC_KEY | PRIVATE_KEY(0x01) = 0x87
const int _evpPkeyPublicKey = 0x86;
const int _evpPkeyKeypair = 0x87;

// ── OpenSSL FFI wrapper ───────────────────────────────────────────────────────
class OpenSslMlKem768 {
  final DynamicLibrary _lib;

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

  OpenSslMlKem768.load(String path) : _lib = DynamicLibrary.open(path) {
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
    _get1EncodedPubKey = _lib.lookupFunction<EvpPkeyGet1EncodedPublicKeyNative,
        EvpPkeyGet1EncodedPublicKeyDart>('EVP_PKEY_get1_encoded_public_key');
    _encapsInit = _lib.lookupFunction<EvpPkeyKemInitNative, EvpPkeyKemInitDart>(
        'EVP_PKEY_encapsulate_init');
    _encapsulate = _lib.lookupFunction<EvpPkeyEncapsulateNative,
        EvpPkeyEncapsulateDart>('EVP_PKEY_encapsulate');
    _decapsInit = _lib.lookupFunction<EvpPkeyKemInitNative, EvpPkeyKemInitDart>(
        'EVP_PKEY_decapsulate_init');
    _decapsulate = _lib.lookupFunction<EvpPkeyDecapsulateNative,
        EvpPkeyDecapsulateDart>('EVP_PKEY_decapsulate');
    _bldNew = _lib.lookupFunction<OsslParamBldNewNative, OsslParamBldNewDart>(
        'OSSL_PARAM_BLD_new');
    _bldFree = _lib.lookupFunction<OsslParamBldFreeNative, OsslParamBldFreeDart>(
        'OSSL_PARAM_BLD_free');
    _bldToParam = _lib.lookupFunction<OsslParamBldToParamNative,
        OsslParamBldToParamDart>('OSSL_PARAM_BLD_to_param');
    _bldPushOctet = _lib.lookupFunction<OsslParamBldPushOctetStringNative,
        OsslParamBldPushOctetStringDart>('OSSL_PARAM_BLD_push_octet_string');
    _paramFree = _lib.lookupFunction<OsslParamFreeNative, OsslParamFreeDart>(
        'OSSL_PARAM_free');
    _fromdataInit = _lib.lookupFunction<EvpPkeyFromdataInitNative,
        EvpPkeyFromdataInitDart>('EVP_PKEY_fromdata_init');
    _fromdata = _lib.lookupFunction<EvpPkeyFromdataNative, EvpPkeyFromdataDart>(
        'EVP_PKEY_fromdata');
    _cryptoFree = _lib.lookupFunction<CryptoFreeNative, CryptoFreeDart>(
        'CRYPTO_free');
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
    // All native buffers must outlive the EVP_PKEY_fromdata call —
    // OSSL_PARAM_BLD stores pointers, not copies.
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

      if (_fromdata(ctx, pkeyPtr, _evpPkeyPublicKey, params) <= 0) {
        throw StateError('EVP_PKEY_fromdata failed');
      }

      return pkeyPtr.value;
    } finally {
      if (ctx != null) _ctxFree(ctx);
      if (params != null) _paramFree(params);
      // Free these only after fromdata has completed
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

      // Query sizes
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
        // Query shared secret size
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

  void freeKey(Pointer<EVP_PKEY> pkey) => _pkeyFree(pkey);
}

// ── Helpers ───────────────────────────────────────────────────────────────────
String hex(List<int> bytes, {int maxBytes = 16}) {
  final shown = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  final h = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  return bytes.length > maxBytes ? '$h... (${bytes.length} bytes)' : h;
}

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _failures = <String>[];

void check(String label, bool condition) {
  final mark = condition ? 'PASS' : 'FAIL';
  print('[$mark] $label');
  if (!condition) _failures.add(label);
}

// ── Main ──────────────────────────────────────────────────────────────────────
void main() {
  const libPath = '/opt/homebrew/opt/openssl@3.6/lib/libcrypto.dylib';
  final ossl = OpenSslMlKem768.load(libPath);
  final pq = PqcKem.kyber768;

  print('=== ML-KEM-768 Cross-Implementation Comparison ===');
  print('    OpenSSL 3.6 (via FFI → libcrypto) vs pqcrypto package\n');

  // ── Test A: OpenSSL keygen → OpenSSL encaps → OpenSSL decaps ─────────────
  print('--- Test A: OpenSSL → OpenSSL (sanity check) ---');
  final (Uint8List opensslPubA, Pointer<EVP_PKEY> opensslKeyA) = ossl.generateKeypair();
  final (Uint8List ctA, Uint8List ssAliceA) = ossl.encapsulate(ossl.importPublicKey(opensslPubA));
  final Uint8List ssBobA = ossl.decapsulate(opensslKeyA, ctA);

  print('  PK:           ${hex(opensslPubA)}');
  print('  Ciphertext:   ${hex(ctA)}');
  print('  Alice SS:     ${hex(ssAliceA)}');
  print('  Bob   SS:     ${hex(ssBobA)}');
  check('OpenSSL encaps/decaps shared secrets match', bytesEqual(ssAliceA, ssBobA));
  ossl.freeKey(opensslKeyA);

  // ── Test B: pqcrypto keygen → pqcrypto encaps → pqcrypto decaps ──────────
  print('\n--- Test B: pqcrypto → pqcrypto (sanity check) ---');
  final (pqPubB, pqSkB) = pq.generateKeyPair();
  final (ctB, ssAliceB) = pq.encapsulate(pqPubB);
  final ssBobB = pq.decapsulate(pqSkB, ctB);

  print('  PK:           ${hex(pqPubB)}');
  print('  Ciphertext:   ${hex(ctB)}');
  print('  Alice SS:     ${hex(ssAliceB)}');
  print('  Bob   SS:     ${hex(ssBobB)}');
  check('pqcrypto encaps/decaps shared secrets match', bytesEqual(ssAliceB, ssBobB));

  // ── Test C: OpenSSL keygen → pqcrypto encaps → OpenSSL decaps ────────────
  print('\n--- Test C: OpenSSL keygen → pqcrypto encaps → OpenSSL decaps ---');
  final (opensslPubC, opensslKeyC) = ossl.generateKeypair();
  print('  OpenSSL PK size: ${opensslPubC.length} bytes');

  final (ctC, ssAliceC) = pq.encapsulate(opensslPubC);
  print('  pqcrypto ciphertext: ${hex(ctC)}');
  print('  pqcrypto SS (Alice): ${hex(ssAliceC)}');

  final ssBobC = ossl.decapsulate(opensslKeyC, Uint8List.fromList(ctC));
  print('  OpenSSL  SS (Bob):   ${hex(ssBobC)}');
  check(
    'OpenSSL keygen + pqcrypto encaps + OpenSSL decaps: shared secrets match',
    bytesEqual(ssAliceC, ssBobC),
  );
  ossl.freeKey(opensslKeyC);

  // ── Test D: pqcrypto keygen → OpenSSL encaps → pqcrypto decaps ───────────
  print('\n--- Test D: pqcrypto keygen → OpenSSL encaps → pqcrypto decaps ---');
  final (pqPubD, pqSkD) = pq.generateKeyPair();
  print('  pqcrypto PK size: ${pqPubD.length} bytes');

  final opensslPubKeyD = ossl.importPublicKey(Uint8List.fromList(pqPubD));
  final (ctD, ssAliceD) = ossl.encapsulate(opensslPubKeyD);
  ossl.freeKey(opensslPubKeyD);
  print('  OpenSSL  ciphertext: ${hex(ctD)}');
  print('  OpenSSL  SS (Alice): ${hex(ssAliceD)}');

  final ssBobD = pq.decapsulate(pqSkD, ctD);
  print('  pqcrypto SS (Bob):   ${hex(ssBobD)}');
  check(
    'pqcrypto keygen + OpenSSL encaps + pqcrypto decaps: shared secrets match',
    bytesEqual(ssAliceD, ssBobD),
  );

  // ── Summary ───────────────────────────────────────────────────────────────
  print('\n=== Summary ===');
  if (_failures.isEmpty) {
    print('[PASS] All tests passed.');
    print('Both implementations conform to FIPS 203 ML-KEM-768:');
    print('  - Ciphertexts produced by one can be decapsulated by the other');
    print('  - Shared secrets are byte-identical across implementations');
  } else {
    print('[FAIL] ${_failures.length} test(s) failed:');
    for (final f in _failures) {
      print('  - $f');
    }
    print('\nInterpretation:');
    print('  Tests A and B verify each implementation is internally consistent.');
    print('  Tests C and D verify cross-implementation interoperability.');
    print('  A failure in C or D means the pqcrypto package deviates from');
    print('  FIPS 203 and cannot exchange keys with OpenSSL ML-KEM-768.');
    exit(1);
  }
}
