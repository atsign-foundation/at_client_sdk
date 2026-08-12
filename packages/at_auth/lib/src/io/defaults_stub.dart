import 'package:at_auth/src/at_auth.dart' show AtServerProbe;
import 'package:at_auth/src/keys/io/at_keys_io.dart';

/// The web/WASM half of the platform-conditional defaults in
/// `defaults_io.dart`, selected when `dart.library.io` is unavailable.
///
/// Both return null, because neither default can exist in a browser: there is no
/// file system for `FileAtKeysIo` to write to and no raw TLS socket for the
/// readiness probe to open. Returning null rather than throwing keeps the
/// failure at the point where the missing thing actually matters — `onboard()`
/// raises `AtAuthenticationException` naming `atKeysIo`, and `validateAtServer`
/// logs that it is skipping the probe — instead of at import or construction.

/// No default key store on the web; supply one via
/// `AtOnboardingRequest.atKeysIo` (e.g. `InMemoryAtKeysIo`).
AtKeysIo? defaultAtKeysIo() => null;

/// No default readiness probe on the web.
AtServerProbe? defaultProbeSocket() => null;
