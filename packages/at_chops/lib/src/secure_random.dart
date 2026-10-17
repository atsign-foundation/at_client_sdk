import 'dart:math';
import 'dart:typed_data';

final Random _rng = Random.secure();

/// [length] bytes from the platform's cryptographically secure random source.
///
/// Internal: the single source every `generateKey`/`generateKeyPair`
/// implementation draws from, so there is one place to audit.
Uint8List secureRandomBytes(int length) {
  final Uint8List out = Uint8List(length);
  for (int i = 0; i < length; i++) {
    out[i] = _rng.nextInt(256);
  }
  return out;
}
