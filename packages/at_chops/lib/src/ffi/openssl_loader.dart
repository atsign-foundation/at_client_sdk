import 'dart:ffi';
import 'dart:io';

import 'package:at_chops/src/ffi/openssl_ffi_bindings.dart';
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
/// fallback strategy. Pass the returned library to an FFI-backed algorithm's
/// `.fromLib` constructor (e.g. [MlKem768FfiAlgo.fromLib],
/// [X25519FfiAlgo.fromLib], [AesGcm256FfiAlgo.fromLib]).
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

/// Returns `true` when [lib] can fetch a usable AES-256-GCM cipher.
///
/// Uses `EVP_CIPHER_fetch` — the OpenSSL 3 provider-aware fetch-by-name, the
/// symmetric-cipher analogue of the `EVP_PKEY_CTX_new_from_name` probe used for
/// ML-DSA/ML-KEM. On a FIPS-/policy-restricted libcrypto where the legacy
/// `EVP_aes_256_gcm` symbol still resolves but the cipher is disabled by the
/// active provider, the fetch returns null, so [AtPqc.aesGcm256] falls back to
/// pure-Dart instead of selecting [AesGcm256FfiAlgo] and then throwing a bare
/// [StateError] at encrypt/decrypt.
bool libCryptoSupportsAesGcm(DynamicLibrary lib) {
  return _libCryptoSupportsCipher(lib, 'AES-256-GCM');
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

/// Fetch-by-name probe for a symmetric cipher, mirroring
/// [_libCryptoSupportsAlgorithm] but for `EVP_CIPHER`, which uses a distinct
/// fetch/free API (`EVP_CIPHER_fetch`/`EVP_CIPHER_free`) from `EVP_PKEY`.
bool _libCryptoSupportsCipher(DynamicLibrary lib, String cipherName) {
  try {
    final cipherFetch = lib.lookupFunction<
        Pointer<EVP_CIPHER> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        Pointer<EVP_CIPHER> Function(
            Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('EVP_CIPHER_fetch');
    final cipherFree = lib.lookupFunction<Void Function(Pointer<EVP_CIPHER>),
        void Function(Pointer<EVP_CIPHER>)>('EVP_CIPHER_free');

    final Pointer<Utf8> name = cipherName.toNativeUtf8();
    try {
      final Pointer<EVP_CIPHER> cipher = cipherFetch(nullptr, name, nullptr);
      if (cipher == nullptr) return false;
      cipherFree(cipher);
      return true;
    } finally {
      calloc.free(name);
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
