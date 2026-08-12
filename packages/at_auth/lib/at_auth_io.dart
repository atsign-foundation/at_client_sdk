/// The `dart:io` surface for at_auth — file-backed `.atKeys` storage and the
/// TLS atServer readiness probe; **not web/wasm compatible**.
///
/// Re-exports everything in `at_auth.dart`, so a `dart:io` host imports this
/// barrel instead of that one and nothing else changes:
///
/// ```dart
/// import 'package:at_auth/at_auth_io.dart';
///
/// // secureSocketProbe restores the atServer readiness poll that at_auth 3.x
/// // did unconditionally; the WASM-safe barrel cannot name a TLS socket.
/// final atAuth = AtAuth.create(probeSocket: secureSocketProbe);
/// final keys = FileAtKeysIo(filePath: (_) => '/path/to/@alice_key.atKeys');
/// ```
library;

export 'at_auth.dart';

/// [FileAtKeysIo], plus `getHomeDirectory` / `getDefaultAtKeysFilePath`.
export 'src/keys/io/file_io.dart';

/// [secureSocketProbe] — the TLS atServer readiness probe.
export 'src/io/probe.dart';
