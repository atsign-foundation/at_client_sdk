import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The page's `crypto.subtle`.
///
/// Throws a [StateError] outside a secure context, where the browser does not
/// provide it.
web.SubtleCrypto subtleCrypto() {
  if (!web.window.isSecureContext) {
    throw StateError('WebCrypto unavailable: not a secure context');
  }
  return web.window.crypto.subtle;
}

/// WebCrypto's `AesCtrParams` dictionary.
extension type AesCtrParams._(JSObject _) implements JSObject {
  external factory AesCtrParams(
      {String name, JSUint8Array counter, int length});
}

/// WebCrypto's `Pbkdf2Params` dictionary.
extension type Pbkdf2Params._(JSObject _) implements JSObject {
  external factory Pbkdf2Params(
      {String name, String hash, JSUint8Array salt, int iterations});
}
