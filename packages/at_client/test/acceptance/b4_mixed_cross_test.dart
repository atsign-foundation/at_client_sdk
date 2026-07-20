/// B4 · Mixed-PQ across atSigns.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 11.
library;

import 'package:test/test.dart';

import 'blockers.dart';

void main() {
  group('B4 · mixed-PQ across atSigns', () {
    test('UC-B4.1 · PQ-ready @alice shares with legacy @bob', () {
      // GIVEN @alice PQ-ready; @bob legacy (only RSA publickey), bob
      //       readiness = n-r.
      // WHEN  alice1 shares or notifies @bob:<k>.app_1.my_apps@alice.
      // THEN  alice writes LEGACY to bob — a per-value symmetric key RSA-wrapped
      //       inline onto the data (the monolithic legacy model) — gated by
      //       bob's n-r readiness. A PQ self-copy via the nskey data path for
      //       alice's own enrollments is allowed INDEPENDENTLY. No write bob
      //       can't read.
      fail('not implemented');
    }, skip: r1);

    test('UC-B4.2 · legacy @alice receives from PQ @bob (the interop question)',
        () {
      // GIVEN @alice legacy (no pqpublickey); @bob PQ-native.
      // WHEN  bob1 shares with @alice.
      // THEN  bob must encapsulate in a scheme alice can read — legacy RSA to
      //       alice's public:publickey@alice, which exists ONLY if alice enabled
      //       the legacy-interop flag (default off). Test outcome: a PQ-native
      //       atSign is PQ-only by default, so a legacy-peer send to it is
      //       UNSUPPORTED unless that flag is on.
      fail('not implemented');
    }, skip: on1);

    test('UC-B4.3 · partially-upgraded @alice shares with @bob', () {
      // GIVEN @alice mixed (alice1 PQ, alice2 legacy); @bob PQ-ready.
      // WHEN  alice1 shares/notifies @bob.
      // THEN  the write TOWARD BOB may take the nskey data path (bob is ready),
      //       but alice's SELF-COPY must stay legacy (alice2 can't read PQ)
      //       until @alice readiness flips. Two directions, two schemes, one
      //       put/notify.
      fail('not implemented');
    }, skip: r1);

    test('UC-B4.4 · @bob finishes upgrading, shared flips to PQ', () {
      // GIVEN @bob was legacy; now all bob enrollments are PQ and bob
      //       readiness = ready.
      // WHEN  alice1 next shares/notifies @bob.
      // THEN  alice writes via the nskey data path to bob; the legacy path is no
      //       longer used toward bob.
      fail('not implemented');
    }, skip: r1);
  });
}
