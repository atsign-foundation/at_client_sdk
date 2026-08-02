/// A1 · Onboard a new atSign (PQ-native).
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 2.
library;

import 'package:test/test.dart';

import 'blockers.dart';

void main() {
  group('A1 · PQ-native onboard', () {
    test('UC-A1.1 · first-enrollment CRAM onboard is PQ-native', () {
      // GIVEN @alice unactivated; aliceS = pq; CRAM activation secret in hand;
      //       no keys exist.
      // WHEN  alice1 runs CRAM onboarding.
      // THEN  alice1.APKAM = pq and authenticates via PQ APKAM (no RSA APKAM);
      //       public:pqpublickey@alice exists and is immutable (a second create
      //       is rejected) and alice1 holds its private; alice1.KP registered in
      //       E1's record but not published (discoverable only via
      //       enroll:listns); NO selfEncryptionKey is minted; readiness may be
      //       ready;
      //       legacy public:publickey@alice is absent by default.
      fail('not implemented');
    }, skip: on1);
  });
}
