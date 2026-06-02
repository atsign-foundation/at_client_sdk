/// dart_pqc — Post-quantum cryptography primitives for Dart.
///
/// Public surface:
///
/// - [KemAlgorithm]       — common KEM interface
/// - [PqcKeyPair]         — raw public/secret key pair
/// - [EncapsulationResult] — ciphertext + shared secret
///
/// Pure-Dart implementations (always available):
/// - [MlKem768PureDart]   — ML-KEM-768 (pure Dart, pqcrypto fork)
/// - [X25519PureDart]     — X25519 ECDH-as-KEM (pure Dart, cryptography package)
///
/// FFI-accelerated OpenSSL implementations (native platforms only):
/// - [MlKem768Ffi]        — ML-KEM-768 via OpenSSL EVP API
/// - [X25519Ffi]          — X25519 via OpenSSL EVP API
///
/// Auto-selected (FFI when libcrypto available, pure Dart otherwise):
/// - [resolveMlKem768]    — returns best available ML-KEM-768
/// - [resolveX25519]      — returns best available X25519

library dart_pqc;

export 'src/dart_pqc_base.dart';
export 'src/kem_resolver.dart';
export 'src/openssl_loader.dart';
export 'src/ml_kem_768.dart';
export 'src/ml_kem_768_ffi.dart';
export 'src/x25519.dart';
export 'src/x25519_ffi.dart';
