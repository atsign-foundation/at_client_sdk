import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Draws a fresh 12-byte AES-GCM nonce from the platform CSPRNG
/// ([Random.secure]).
///
/// Library-internal: the GCM algorithms own nonce generation — one fresh
/// nonce per encryption, prepended to the ciphertext — precisely so that no
/// caller can ever reuse a (key, nonce) pair. Nonce reuse under GCM leaks
/// the XOR of the plaintexts AND the GHASH authentication key (Joux's
/// "forbidden attack"), enabling forgery of every message under that key.
@internal
Uint8List generateGcmNonce() {
  final Random rng = Random.secure();
  final Uint8List nonce = Uint8List(12);
  for (int i = 0; i < nonce.length; i++) {
    nonce[i] = rng.nextInt(256);
  }
  return nonce;
}
