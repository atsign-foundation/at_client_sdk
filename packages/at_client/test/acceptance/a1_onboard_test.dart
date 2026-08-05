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
      // THEN  alice1.APKAM = pq and authenticates via PQ APKAM (no RSA APKAM
      //       needed for auth); public:pq_signing_root@alice exists and is
      //       immutable (a second create is rejected) and alice1 holds its
      //       private; alice1.KP registered in E1's record but not published
      //       (discoverable only via enroll:listns). Legacy material is STILL
      //       cut and published BY DEFAULT (decisions 37, reversing the old
      //       Decision #1): the RSA encryption keypair + selfEncryptionKey are
      //       minted (the PQ data path never touches them) and
      //       public:publickey@alice is present unless the opt-OUT flag is
      //       set.
      fail('not implemented');
    }, skip: on1);
  });
}
