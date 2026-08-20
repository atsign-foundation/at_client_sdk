// The expiry timer must not spin when its sweep cannot make progress.
//
// `LocalSecondary.nextExpiryAt()` reports the earliest expiry in the store
// INCLUDING ones already past — unlike its sibling `nextAvailableAt()`, which
// excludes crossings that have already happened. Both backends of
// at_persistence_secondary_server agree on that asymmetry: Hive skips
// `!avail.isAfter(cutoff)` for availability and applies no cutoff at all to
// expiry, and SQLite filters `available_at > ?` while taking a bare
// `MIN(expires_at)`. A past expiry therefore arms `Duration.zero`, on the
// assumption that the sweep about to run removes the record and moves the
// minimum forward.
//
// That assumption fails for a record the client cannot delete. The sweep logs
// the refusal and keeps going, the record stays, the minimum does not move,
// and the next arm is `Duration.zero` again — a cycle that cannot change its
// own outcome. Measured before the fix, in one functional pack run: 186,994
// sweeps in 5.7 seconds on a single `_nskeylock` record, with two more keys
// doing the same, together 47% of that run's log lines. Reachable in ordinary
// use because an nskey mint lock is released by its ttl and by nothing else,
// so every mint and every rotation leaves a record that expires in place.
//
// ⚠️ WHAT THESE TESTS DO NOT COVER: that `_onExpiryFire` passes
// `afterFruitlessSweep: removed == 0`. The decision below is pinned; the one
// line that feeds it is not, because observing it needs a fully built
// `AtClientImpl` with an injected `LocalSecondary`. A change that always
// passed `false` would leave every test here green and restore the spin.

import 'package:at_client/src/client/at_client_impl.dart';
import 'package:test/test.dart';

void main() {
  group('expiryTimerDelay', () {
    test('a future expiry is waited for exactly', () {
      expect(
          AtClientImpl.expiryTimerDelay(Duration(seconds: 42),
              afterFruitlessSweep: false),
          equals(Duration(seconds: 42)));
      // A fruitless sweep neither shortens nor lengthens a future expiry: the
      // backoff exists only to break a zero-delay cycle.
      expect(
          AtClientImpl.expiryTimerDelay(Duration(seconds: 42),
              afterFruitlessSweep: true),
          equals(Duration(seconds: 42)));
    });

    test('a past expiry fires immediately when the sweep is making progress',
        () {
      // The normal case, and what the zero delay is for: several keys expire
      // at once, each sweep removes some, the minimum keeps moving forward.
      expect(
          AtClientImpl.expiryTimerDelay(Duration(seconds: -3),
              afterFruitlessSweep: false),
          equals(Duration.zero));
    });

    test('a past expiry after a sweep that removed nothing backs off', () {
      // The whole point. Zero here is the busy loop.
      final delay = AtClientImpl.expiryTimerDelay(Duration(seconds: -3),
          afterFruitlessSweep: true);
      expect(delay, greaterThan(Duration.zero),
          reason: 'a zero delay re-runs the same computation over the same '
              'state, which is what spun 186,994 times in 5.7 seconds');
      expect(delay, equals(Duration(seconds: 30)));
    });

    test('an expiry exactly now takes the future branch, not the past one', () {
      // `Duration.zero` is not negative, so it is treated as "due now" and
      // fires immediately — and a fruitless sweep cannot back it off. Pinned
      // because `isNegative` rather than `<= 0` is what decides the branch,
      // and the two differ only here.
      expect(
          AtClientImpl.expiryTimerDelay(Duration.zero,
              afterFruitlessSweep: true),
          equals(Duration.zero));
    });
  });
}
