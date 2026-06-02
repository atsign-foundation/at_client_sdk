import 'dart:ffi';
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

// EVP_PKEY_derive_init / EVP_PKEY_derive_set_peer / EVP_PKEY_derive — for X25519 ECDH
typedef EvpPkeyDeriveInitNative = Int32 Function(Pointer<EVP_PKEY_CTX>);
typedef EvpPkeyDeriveInitDart = int Function(Pointer<EVP_PKEY_CTX>);

typedef EvpPkeyDeriveSetPeerNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<EVP_PKEY>);
typedef EvpPkeyDeriveSetPeerDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<EVP_PKEY>);

typedef EvpPkeyDeriveNative = Int32 Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Uint8>, Pointer<IntPtr>);
typedef EvpPkeyDeriveDart = int Function(
    Pointer<EVP_PKEY_CTX>, Pointer<Uint8>, Pointer<IntPtr>);

// EVP_PKEY_get_raw_public_key / EVP_PKEY_get_raw_private_key — for X25519 key extraction
typedef EvpPkeyGetRawKeyNative = Int32 Function(
    Pointer<EVP_PKEY>, Pointer<Uint8>, Pointer<IntPtr>);
typedef EvpPkeyGetRawKeyDart = int Function(
    Pointer<EVP_PKEY>, Pointer<Uint8>, Pointer<IntPtr>);

// EVP_PKEY_new_raw_private_key — reconstruct X25519 key from bytes
typedef EvpPkeyNewRawPrivateKeyNative = Pointer<EVP_PKEY> Function(
    Int32, Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef EvpPkeyNewRawPrivateKeyDart = Pointer<EVP_PKEY> Function(
    int, Pointer<Void>, Pointer<Uint8>, int);

// EVP_PKEY_new_raw_public_key — reconstruct X25519 public key from bytes
typedef EvpPkeyNewRawPublicKeyNative = Pointer<EVP_PKEY> Function(
    Int32, Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef EvpPkeyNewRawPublicKeyDart = Pointer<EVP_PKEY> Function(
    int, Pointer<Void>, Pointer<Uint8>, int);

// EVP_MD_CTX_new / free — for Ed25519 sign/verify
typedef EvpMdCtxNewNative = Pointer<Void> Function();
typedef EvpMdCtxNewDart = Pointer<Void> Function();

typedef EvpMdCtxFreeNative = Void Function(Pointer<Void>);
typedef EvpMdCtxFreeDart = void Function(Pointer<Void>);

// EVP_DigestSignInit — init sign context (Ed25519: md=null, type from pkey)
typedef EvpDigestSignInitNative = Int32 Function(Pointer<Void>,
    Pointer<Pointer<EVP_PKEY_CTX>>, Pointer<Void>, Pointer<Void>, Pointer<EVP_PKEY>);
typedef EvpDigestSignInitDart = int Function(Pointer<Void>,
    Pointer<Pointer<EVP_PKEY_CTX>>, Pointer<Void>, Pointer<Void>, Pointer<EVP_PKEY>);

// EVP_DigestSign — one-shot sign (OpenSSL 3)
typedef EvpDigestSignNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, IntPtr);
typedef EvpDigestSignDart = int Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<IntPtr>, Pointer<Uint8>, int);

// EVP_DigestVerifyInit
typedef EvpDigestVerifyInitNative = Int32 Function(Pointer<Void>,
    Pointer<Pointer<EVP_PKEY_CTX>>, Pointer<Void>, Pointer<Void>, Pointer<EVP_PKEY>);
typedef EvpDigestVerifyInitDart = int Function(Pointer<Void>,
    Pointer<Pointer<EVP_PKEY_CTX>>, Pointer<Void>, Pointer<Void>, Pointer<EVP_PKEY>);

// EVP_DigestVerify — one-shot verify (OpenSSL 3)
typedef EvpDigestVerifyNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, IntPtr, Pointer<Uint8>, IntPtr);
typedef EvpDigestVerifyDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int);

// ── OpenSSL selection constants ───────────────────────────────────────────────
const int evpPkeyPublicKey = 0x86;
const int evpPkeyKeypair = 0x87;

// NID_X25519 = 1034
const int nidX25519 = 1034;

// NID_ED25519 = 1087
const int nidEd25519 = 1087;
