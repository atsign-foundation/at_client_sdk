import 'dart:typed_data';

sealed class UnlockSecret {
  const UnlockSecret();
}

final class PrfSecret extends UnlockSecret {
  final Uint8List output;

  PrfSecret(this.output) {
    if (output.length != 32) {
      throw ArgumentError('PRF output must be 32 bytes');
    }
  }
}
