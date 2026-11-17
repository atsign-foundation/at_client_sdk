import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

void main() {
  group('PrfSecret', () {
    test('rejects length != 32', () {
      expect(() => PrfSecret(Uint8List(31)), throwsArgumentError);
      expect(() => PrfSecret(Uint8List(33)), throwsArgumentError);
      expect(() => PrfSecret(Uint8List(32)), returnsNormally);
    });

    test('wipe zeroes the output', () {
      final secret = PrfSecret(Uint8List.fromList(List.filled(32, 7)));
      secret.wipe();
      expect(secret.output, everyElement(0));
    });
  });
}
