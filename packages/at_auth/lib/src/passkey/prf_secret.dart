import 'dart:typed_data';

/// The 32-byte PRF output of a passkey assertion.
///
/// Holds the buffer the client received; the holder wipes it once the
/// derivation has consumed it.
class PrfSecret {
  final Uint8List output;

  PrfSecret(this.output) {
    if (output.length != 32) {
      throw ArgumentError('PRF output must be 32 bytes');
    }
  }

  /// Overwrites [output] with zeroes. Only this buffer is cleared; copies made
  /// elsewhere are not tracked.
  void wipe() => output.fillRange(0, output.length, 0);
}
