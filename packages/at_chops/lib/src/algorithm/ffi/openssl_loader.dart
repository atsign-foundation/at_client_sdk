import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Candidate libcrypto paths tried in order when [_envVar] is unset or fails.
const List<String> _candidates = [
  // macOS — Homebrew Apple Silicon
  '/opt/homebrew/lib/libcrypto.dylib',
  // macOS — Homebrew Intel
  '/usr/local/lib/libcrypto.dylib',
  // Linux — OpenSSL 3
  'libcrypto.so.3',
  // Linux — generic fallback
  'libcrypto.so',
];

const String _envVar = 'AT_CHOPS_LIBCRYPTO_PATH';

/// Try to open libcrypto from the path in [_envVar], then from [_candidates].
///
/// Returns a [DynamicLibrary] on the first successful load, or `null` if every
/// candidate fails. Never throws.
///
/// at_chops does not call this automatically — consumers decide their own
/// fallback strategy. Pass the returned library to [MlKem768FfiAlgo.fromLib]
/// or [X25519FfiAlgo.fromLib] when constructing FFI-backed algorithms.
///
/// If [loadedPath] is provided it will be set to the path that was
/// successfully opened, which callers can use to verify whether the env-var
/// path or a fallback candidate was used.
DynamicLibrary? tryLoadLibCrypto({StringBuffer? loadedPath}) {
  final envPath = Platform.environment[_envVar];
  if (envPath != null) {
    final lib = _tryOpen(envPath);
    if (lib != null) {
      loadedPath?.write(envPath);
      return lib;
    }
    // The env var was set but the path failed to open. The most common cause
    // is pointing at a versioned symlink (e.g. libcrypto.so.3): the dynamic
    // linker resolves its baked-in SONAME against system paths and may find an
    // older system OpenSSL instead of the intended one.
    // Fix: set $_envVar to the real .so file — resolve symlinks first:
    //   export $_envVar=$(realpath /your/openssl/lib/libcrypto.so.3)
    stderr.writeln(
      'at_chops warning: $_envVar="$envPath" is set but could not be opened. '
      'Falling back to system candidates. '
      'Tip: if the path is a versioned symlink, point to the real file instead: '
      'export $_envVar=\$(realpath "$envPath")',
    );
  }
  for (final path in _candidates) {
    final lib = _tryOpen(path);
    if (lib != null) {
      loadedPath?.write(path);
      return lib;
    }
  }
  return null;
}

/// Returns `true` when [lib] supports the ML-KEM-768 algorithm.
///
/// ML-KEM-768 was added to the OpenSSL default provider in OpenSSL 3.3.
/// Older 3.x builds (e.g. the 3.0.x shipped with Ubuntu 22.04/24.04) load
/// fine but reject `EVP_PKEY_CTX_new_from_name("ML-KEM-768", ...)`.
/// Call this before constructing [MlKem768FfiAlgo] to gate FFI tests or
/// runtime fallback decisions.
bool libCryptoSupportsMlKem768(DynamicLibrary lib) {
  return _libCryptoSupportsAlgorithm(lib, 'ML-KEM-768');
}

/// Returns `true` when [lib] supports the ML-DSA-65 algorithm.
///
/// ML-DSA-65 was added to the OpenSSL default provider in OpenSSL 3.3.
/// Call this before constructing [MlDsa65FfiAlgo] to gate FFI tests or
/// runtime fallback decisions.
bool libCryptoSupportsMlDsa65(DynamicLibrary lib) {
  return _libCryptoSupportsAlgorithm(lib, 'ML-DSA-65');
}

/// Returns `true` when [lib] exposes `EVP_aes_256_gcm` (available in every
/// OpenSSL 1.0+ build, so this essentially just confirms the symbol resolves).
///
/// Call this before constructing [AesGcm256FfiAlgo] to confirm the symbol is
/// present — it is effectively always true for any usable libcrypto.
bool libCryptoSupportsAesGcm(DynamicLibrary lib) {
  try {
    lib.lookup<NativeFunction<Pointer<Void> Function()>>('EVP_aes_256_gcm');
    return true;
  } catch (_) {
    return false;
  }
}

bool _libCryptoSupportsAlgorithm(DynamicLibrary lib, String algorithmName) {
  try {
    final ctxNewFromName = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>)>(
      'EVP_PKEY_CTX_new_from_name',
    );
    final ctxFree = lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('EVP_PKEY_CTX_free');

    final Pointer<Utf8> algName = algorithmName.toNativeUtf8();
    try {
      final Pointer<Void> ctx = ctxNewFromName(nullptr, algName, nullptr);
      if (ctx == nullptr) return false;
      ctxFree(ctx);
      return true;
    } finally {
      calloc.free(algName);
    }
  } catch (_) {
    return false;
  }
}

DynamicLibrary? _tryOpen(String path) {
  try {
    return DynamicLibrary.open(path);
  } catch (_) {
    return null;
  }
}
