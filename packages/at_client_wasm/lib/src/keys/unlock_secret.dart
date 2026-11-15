import 'dart:convert';
import 'dart:math';
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

final class PassphraseSecret extends UnlockSecret {
  final String passphrase;

  PassphraseSecret(this.passphrase);

  /// 32 random bytes from Random.secure(), base64url without padding.
  static PassphraseSecret generate() {
    final random = Random.secure();
    final bytes =
        Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    return PassphraseSecret(b64);
  }
}
