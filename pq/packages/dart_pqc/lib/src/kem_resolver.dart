import 'dart:ffi';

import 'dart_pqc_base.dart';
import 'ml_kem_768.dart';
import 'ml_kem_768_ffi.dart';
import 'openssl_loader.dart';
import 'x25519.dart';
import 'x25519_ffi.dart';

// Cached resolved instances (null = not yet resolved).
KemAlgorithm? _mlKem768;
KemAlgorithm? _x25519;

/// Return the best available ML-KEM-768 implementation.
///
/// Tries FFI-accelerated OpenSSL first; falls back to pure Dart if libcrypto
/// cannot be loaded.
KemAlgorithm resolveMlKem768() => _mlKem768 ??= _buildMlKem768();

/// Return the best available X25519 implementation.
///
/// Tries FFI-accelerated OpenSSL first; falls back to pure Dart if libcrypto
/// cannot be loaded.
KemAlgorithm resolveX25519() => _x25519 ??= _buildX25519();

KemAlgorithm _buildMlKem768() {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if (lib != null) return MlKem768Ffi.fromLib(lib);
  return MlKem768PureDart.instance;
}

KemAlgorithm _buildX25519() {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if (lib != null) return X25519Ffi.fromLib(lib);
  return X25519PureDart.instance;
}
