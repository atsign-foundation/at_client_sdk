/// dart_pqc — Post-quantum and modern cryptographic primitives for Dart.
///
/// Each primitive ships with two tiers:
///   - FFI-accelerated OpenSSL 3 (native platforms where libcrypto is available)
///   - Pure-Dart fallback (all platforms)
///
/// ML-KEM-768 (FIPS 203 key encapsulation):
/// - [MlKem768PureDart]  — pure Dart (pqcrypto fork)
/// - [MlKem768Ffi]       — OpenSSL FFI
/// - [resolveMlKem768]   — auto-select best available
///
/// X25519 (Diffie-Hellman key agreement):
/// - [X25519PureDart]    — pure Dart (cryptography package)
/// - [X25519Ffi]         — OpenSSL FFI
/// - [resolveX25519]     — auto-select best available
///
/// Ed25519 (signing):
/// - [Ed25519PureDart]   — pure Dart (cryptography package)
/// - [Ed25519Ffi]        — OpenSSL FFI
/// - [resolveEd25519]    — auto-select best available
///
/// X-Wing KEM (ML-KEM-768 + X25519 hybrid, draft-connolly-cfrg-xwing-kem-06):
/// - [XWingPureDart]     — pure Dart fallback (pqcrypto + cryptography)
/// - [XWingFfi]          — OpenSSL FFI
/// - [resolveXWing]      — auto-select best available (never throws)
///
/// ML-DSA-65 (FIPS 204 lattice signing):
/// - [MlDsa65Ffi]        — OpenSSL FFI (no pure-Dart fallback)
/// - [resolveMlDsa65]    — returns FFI impl or throws if libcrypto unavailable

library dart_pqc;

export 'src/dart_pqc_base.dart';
export 'src/openssl_loader.dart';
export 'src/ml_kem_768.dart';
export 'src/ml_kem_768_ffi.dart';
export 'src/x25519.dart';
export 'src/x25519_ffi.dart';
export 'src/ed25519.dart';
export 'src/ed25519_ffi.dart';
export 'src/xwing_ffi.dart';
export 'src/xwing_pure_dart.dart';
export 'src/ml_dsa_65_ffi.dart';
export 'src/resolver.dart';
export 'src/hpke.dart';
