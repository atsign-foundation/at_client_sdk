import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtNetworkTimeouts', () {
    test('maxAllowed is 30 seconds', () {
      expect(AtNetworkTimeouts.maxAllowed, const Duration(seconds: 30));
    });

    test('cap clamps values above maxAllowed down to maxAllowed', () {
      expect(AtNetworkTimeouts.cap(const Duration(minutes: 5)),
          AtNetworkTimeouts.maxAllowed);
      expect(AtNetworkTimeouts.cap(const Duration(seconds: 31)),
          AtNetworkTimeouts.maxAllowed);
    });

    test('cap passes through values within range unchanged', () {
      expect(AtNetworkTimeouts.cap(const Duration(seconds: 5)),
          const Duration(seconds: 5));
      expect(AtNetworkTimeouts.cap(AtNetworkTimeouts.maxAllowed),
          AtNetworkTimeouts.maxAllowed);
    });

    test('cap clamps negative values to zero', () {
      expect(AtNetworkTimeouts.cap(const Duration(seconds: -1)), Duration.zero);
    });

    test('effectiveDefault never exceeds maxAllowed', () {
      expect(AtNetworkTimeouts.effectiveDefault,
          lessThanOrEqualTo(AtNetworkTimeouts.maxAllowed));
    });
  });
}
