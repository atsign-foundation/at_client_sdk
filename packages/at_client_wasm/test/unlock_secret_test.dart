import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:test/test.dart';

void main() {
  group('UnlockSecret', () {
    test('PrfSecret rejects length != 32', () {
      expect(() => PrfSecret(Uint8List(31)), throwsArgumentError);
      expect(() => PrfSecret(Uint8List(33)), throwsArgumentError);
      expect(() => PrfSecret(Uint8List(32)), returnsNormally);
    });

    test('PassphraseSecret generate gives distinct 43-char values', () {
      final secret1 = PassphraseSecret.generate();
      final secret2 = PassphraseSecret.generate();

      expect(secret1.passphrase.length,
          43); // 32 bytes base64url encoded without padding is 43 chars
      expect(secret2.passphrase.length, 43);
      expect(secret1.passphrase, isNot(secret2.passphrase));
    });
  });
}
