/// The [AtAuth] package contains common logic for onboarding/authenticating an
/// atSign to a secondary server.
///
/// This is the barrel to import. It carries the whole package: everything in
/// `at_auth_web.dart` plus the two pieces that need `dart:io` — `FileAtKeysIo`
/// for `.atKeys` files and `secureSocketProbe` for the TLS atServer readiness
/// probe. Both are wired up as defaults automatically, so ordinary use needs
/// nothing extra:
///
/// ```dart
/// import 'package:at_auth/at_auth.dart';
///
/// final atAuth = AtAuth.create();
/// final request = AtOnboardingRequest('@alice')
///   ..atKeysIo = FileAtKeysIo(filePath: (_) => '/path/to/@alice_key.atKeys');
/// ```
///
/// **Building for the web?** Import `package:at_auth/at_auth_web.dart` instead.
/// It exports this barrel's platform-neutral subset and names no `dart:io` type.
/// The split is by barrel rather than enforced by the compiler: `dart compile
/// wasm` accepts `dart:io` and fails at *runtime*, so importing this barrel in a
/// browser build will compile and then throw the first time a file or socket is
/// touched.
library;

export 'at_auth_web.dart';

/// [FileAtKeysIo], plus `getHomeDirectory` / `getDefaultAtKeysFilePath`.
export 'src/keys/io/file_io.dart';

/// [secureSocketProbe] — the TLS atServer readiness probe.
export 'src/io/probe.dart';
