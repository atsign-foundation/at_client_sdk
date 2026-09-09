// The expiry timer must not spin when its sweep cannot make progress.
//
// `LocalSecondary.nextExpiryAt()` includes expiries already past, so a past
// expiry arms `Duration.zero` on the assumption that the sweep about to run
// removes the record and moves the minimum forward. A record the client cannot
// delete breaks that assumption: the record stays, the minimum does not move,
// and the next arm is `Duration.zero` again — so a sweep that removed nothing
// backs the next one off instead.
//
// NOTE: nothing here pins that `_onExpiryFire` passes
// `afterFruitlessSweep: removed == 0`. A change that always passed `false`
// would leave every test in this file green and restore the spin.

import 'package:at_client/src/client/at_client_impl.dart';
import 'package:test/test.dart';

void main() {
  group('expiryTimerDelay', () {
    test('a future expiry is waited for exactly', () {
      expect(
          AtClientImpl.expiryTimerDelay(Duration(seconds: 42),
              afterFruitlessSweep: false),
          equals(Duration(seconds: 42)));
      expect(
          AtClientImpl.expiryTimerDelay(Duration(seconds: 42),
              afterFruitlessSweep: true),
          equals(Duration(seconds: 42)));
    });

    test('a past expiry fires immediately when the sweep is making progress',
        () {
      expect(
          AtClientImpl.expiryTimerDelay(Duration(seconds: -3),
              afterFruitlessSweep: false),
          equals(Duration.zero));
    });

    test('a past expiry after a sweep that removed nothing backs off', () {
      final delay = AtClientImpl.expiryTimerDelay(Duration(seconds: -3),
          afterFruitlessSweep: true);
      expect(delay, greaterThan(Duration.zero),
          reason: 'a zero delay re-runs the same computation over the same '
              'state, which is what spun 186,994 times in 5.7 seconds');
      expect(delay, equals(Duration(seconds: 30)));
    });

    test('an expiry exactly now takes the future branch, not the past one', () {
      // NOTE: `isNegative`, not `<= 0`, decides the branch, and the two differ
      // only here.
      expect(
          AtClientImpl.expiryTimerDelay(Duration.zero,
              afterFruitlessSweep: true),
          equals(Duration.zero));
    });
  });
}
