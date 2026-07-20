/// B3 · Mixed-PQ within one atSign.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 10.
library;

import 'package:test/test.dart';

import 'blockers.dart';

void main() {
  group('B3 · mixed-PQ within one atSign', () {
    test('UC-B3.1 · an upgraded enrollment still writes legacy for an '
        'un-upgraded sibling', () {
      // GIVEN alice1 is PQ (holds the nskey/pqpublickey privates), alice2 is
      //       still legacy-only; @alice readiness = n-r.
      // WHEN  alice1 puts or notifies a self key both must read.
      // THEN  alice1 writes/notifies LEGACY — the scheme alice2 can read — until
      //       readiness flips. Migration invariant: write only what every reader
      //       supports. Applies to put AND notify alike.
      fail('not implemented');
    }, skip: r1);

    test('UC-B3.2 · readiness flips once all @alice enrollments are PQ', () {
      // GIVEN all @alice enrollments now PQ; the operator (or auto-detect)
      //       flips readiness to ready.
      // WHEN  alice1 writes/notifies self data.
      // THEN  self data goes via the nskey data path — at/nskey conveys the CK
      //       and at/symmetric/AES/GCM encrypts the data; the data is never
      //       encapsulated directly to the nskey/pqpublickey. No @alice
      //       enrollment loses access.
      fail('not implemented');
    }, skip: r1);
  });
}
