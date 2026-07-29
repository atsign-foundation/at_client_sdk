/// VM/native surface for at_auth — file-backed `.atKeys` storage and the TLS
/// socket probe. Not web/wasm compatible; `at_auth.dart` is the wasm-safe
/// surface, and this barrel re-exports it, so importing this one is enough.
library;

export 'at_auth.dart';

// FileAtKeysIo, getDefaultAtKeysFilePath, getHomeDirectory — all on `dart:io`
// File/Platform.
export 'src/keys/io/file_io.dart';
// defaultProbeSocket — the SecureSocket reachability probe to inject into
// AtAuth.create.
export 'src/auth/socket_probe_io.dart';
