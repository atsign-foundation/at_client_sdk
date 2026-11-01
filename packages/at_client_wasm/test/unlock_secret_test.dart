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
  });
}
