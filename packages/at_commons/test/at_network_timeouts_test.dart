import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtNetworkTimeouts', () {
    test('maxAllowed is 60 seconds', () {
      expect(AtNetworkTimeouts.maxAllowed, const Duration(seconds: 60));
    });

    test('cap clamps values above maxAllowed down to maxAllowed', () {
      expect(AtNetworkTimeouts.cap(const Duration(minutes: 5)),
          AtNetworkTimeouts.maxAllowed);
      expect(AtNetworkTimeouts.cap(const Duration(seconds: 90)),
          AtNetworkTimeouts.maxAllowed);
    });

    test('cap passes through values within range unchanged', () {
      expect(AtNetworkTimeouts.cap(const Duration(seconds: 5)),
          const Duration(seconds: 5));
      // 45s is above the 30s default but below the 60s ceiling.
      expect(AtNetworkTimeouts.cap(const Duration(seconds: 45)),
          const Duration(seconds: 45));
      expect(AtNetworkTimeouts.cap(AtNetworkTimeouts.maxAllowed),
          AtNetworkTimeouts.maxAllowed);
    });

    test('defaultTimeout is 30 seconds', () {
      expect(AtNetworkTimeouts.defaultTimeout, const Duration(seconds: 30));
    });

    test('cap clamps negative values to zero', () {
      expect(AtNetworkTimeouts.cap(const Duration(seconds: -1)), Duration.zero);
    });

    test('effectiveDefault never exceeds maxAllowed', () {
      expect(AtNetworkTimeouts.effectiveDefault,
          lessThanOrEqualTo(AtNetworkTimeouts.maxAllowed));
    });

    test('defaultOnboardingTimeout is 5 minutes and longer than defaultTimeout',
        () {
      expect(AtNetworkTimeouts.defaultOnboardingTimeout,
          const Duration(minutes: 5));
      // The onboarding poll waits for provisioning, so it must be much longer
      // than the per-attempt default and is intentionally above the 60s op cap.
      expect(AtNetworkTimeouts.defaultOnboardingTimeout,
          greaterThan(AtNetworkTimeouts.defaultTimeout));
      expect(AtNetworkTimeouts.defaultOnboardingTimeout,
          greaterThan(AtNetworkTimeouts.maxAllowed));
    });

    test('defaultResponseBudget is 90 seconds and exceeds the operation cap',
        () {
      // Pins the long-standing default of OutboundMessageListener.read's
      // maxWaitMilliSeconds, so adopting it there changes no behaviour.
      expect(AtNetworkTimeouts.defaultResponseBudget,
          const Duration(seconds: 90));
      // It bounds a whole response rather than one operation, so it is exempt
      // from the cap - and its own default already sits above the ceiling.
      expect(AtNetworkTimeouts.defaultResponseBudget,
          greaterThan(AtNetworkTimeouts.maxAllowed));
      // A response is many next-bytes waits in a row; the budget bounds the sum.
      expect(AtNetworkTimeouts.defaultResponseBudget,
          greaterThan(AtNetworkTimeouts.defaultTimeout));
    });
  });
}
