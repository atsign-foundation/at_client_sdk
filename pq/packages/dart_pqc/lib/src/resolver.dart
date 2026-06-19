import 'dart:ffi';
import 'dart:io';

import 'dart_pqc_base.dart';
import 'ml_kem_768.dart';
import 'ml_kem_768_ffi.dart';
import 'ml_dsa_65_ffi.dart';
import 'x25519.dart';
import 'x25519_ffi.dart';
import 'ed25519.dart';
import 'ed25519_ffi.dart';
import 'xwing_ffi.dart';
import 'xwing_pure_dart.dart';
import 'openssl_loader.dart';

// libcrypto is probed once at startup for the process lifetime.
final DynamicLibrary? _lib = tryLoadLibCrypto();

// Implementations are selected once, eagerly, at startup.
final MlKem768Algorithm _mlKem768 =
    _lib != null ? MlKem768Ffi.fromLib(_lib!) : MlKem768PureDart.instance;

final X25519Algorithm _x25519 =
    _lib != null ? X25519Ffi.fromLib(_lib!) : X25519PureDart.instance;

final Ed25519Algorithm _ed25519 =
    _lib != null ? Ed25519Ffi.fromLib(_lib!) : Ed25519PureDart.instance;

final XWingAlgorithm _xwing =
    _lib != null ? XWingFfi.fromLib(_lib!) : XWingPureDart.instance;

final MlDsa65Algorithm? _mlDsa65 =
    _lib != null ? MlDsa65Ffi.fromLib(_lib!) : null;

/// Return the best available ML-KEM-768 implementation.
///
/// Tries FFI-accelerated OpenSSL first; falls back to pure Dart if libcrypto
/// cannot be loaded. Prints the resolved implementation on first call.
MlKem768Algorithm resolveMlKem768() {
  stderr.writeln('[dart_pqc] ML-KEM-768 → ${_mlKem768.runtimeType}');
  return _mlKem768;
}

/// Return the best available X25519 implementation.
///
/// Tries FFI-accelerated OpenSSL first; falls back to pure Dart if libcrypto
/// cannot be loaded. Prints the resolved implementation on first call.
X25519Algorithm resolveX25519() {
  stderr.writeln('[dart_pqc] X25519    → ${_x25519.runtimeType}');
  return _x25519;
}

/// Return the best available Ed25519 implementation.
///
/// Tries FFI-accelerated OpenSSL first; falls back to pure Dart if libcrypto
/// cannot be loaded. Prints the resolved implementation on first call.
Ed25519Algorithm resolveEd25519() {
  stderr.writeln('[dart_pqc] Ed25519   → ${_ed25519.runtimeType}');
  return _ed25519;
}

/// Return the best available X-Wing KEM implementation.
///
/// Prefers FFI-accelerated OpenSSL; falls back to pure Dart if libcrypto
/// cannot be loaded. Never throws.
XWingAlgorithm resolveXWing() {
  stderr.writeln('[dart_pqc] X-Wing    → ${_xwing.runtimeType}');
  return _xwing;
}

/// Return the ML-DSA-65 implementation (FFI-only — requires libcrypto).
///
/// Throws [StateError] if libcrypto is not available (no pure-Dart fallback).
MlDsa65Algorithm resolveMlDsa65() {
  if (_mlDsa65 == null) {
    throw StateError(
        '[dart_pqc] ML-DSA-65 requires OpenSSL 3 (libcrypto not found). '
        'Set DART_PQC_LIBCRYPTO_PATH or install OpenSSL 3.3+.');
  }
  stderr.writeln('[dart_pqc] ML-DSA-65 → ${_mlDsa65!.runtimeType}');
  return _mlDsa65!;
}
