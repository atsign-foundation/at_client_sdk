import 'dart:ffi';
import 'dart:io';

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

const String _envVar = 'DART_PQC_LIBCRYPTO_PATH';

/// Try to open libcrypto from the path in [_envVar], then from [_candidates].
///
/// Returns a [DynamicLibrary] on the first successful load, or `null` if every
/// candidate fails. Never throws.
DynamicLibrary? tryLoadLibCrypto() {
  final envPath = Platform.environment[_envVar];
  if (envPath != null) {
    final lib = _tryOpen(envPath);
    if (lib != null) return lib;
  }
  for (final path in _candidates) {
    final lib = _tryOpen(path);
    if (lib != null) return lib;
  }
  return null;
}

DynamicLibrary? _tryOpen(String path) {
  try {
    return DynamicLibrary.open(path);
  } catch (_) {
    return null;
  }
}
