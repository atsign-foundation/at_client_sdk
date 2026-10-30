import 'package:at_chops/src/algorithm/spec/output_length.dart';
import 'package:test/test.dart';

void main() {
  group('checkOutputLength', () {
    test('does nothing when actual equals expected', () {
      expect(() => checkOutputLength(32, 32, operation: 'op', label: 'thing'),
          returnsNormally);
    });

    test('throws StateError with operation/label/lengths when mismatched', () {
      expect(
          () => checkOutputLength(31, 32, operation: 'X-Wing', label: 'seed'),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              'X-Wing produced a 31-byte seed, expected 32')));
    });
  });
}
