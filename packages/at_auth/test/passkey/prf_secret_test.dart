import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

void main() {
  group('PrfSecret', () {
    test('rejects length != 32', () {
      expect(() => PrfSecret(Uint8List(31)..[0] = 1), throwsArgumentError);
      expect(() => PrfSecret(Uint8List(33)..[0] = 1), throwsArgumentError);
      expect(() => PrfSecret(Uint8List(32)..[31] = 1), returnsNormally);
    });

    test('refuses an output of 32 zero bytes', () {
      expect(
          () => PrfSecret(Uint8List(32)),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
              'PRF output must not be all zeroes')));
    });

    test('accepts an output whose only non-zero byte is the last', () {
      final bytes = Uint8List(32)..[31] = 1;
      expect(PrfSecret(bytes).output, same(bytes));
    });

    test('wipe zeroes the buffer it was given', () {
      final bytes = Uint8List.fromList(List.filled(32, 7));
      PrfSecret(bytes).wipe();
      expect(bytes, everyElement(0));
    });

    test('the output cannot be read once wiped', () {
      final secret = PrfSecret(Uint8List.fromList(List.filled(32, 7)));
      expect(secret.output, everyElement(7));
      secret.wipe();
      expect(
          () => secret.output,
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', 'the PRF output was wiped')));
    });
  });
}
