/// A1 · Onboard a new atSign (PQ-native).
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 2.
library;

import 'package:test/test.dart';

import 'proven_elsewhere.dart';

void main() {
  group('A1 · PQ-native onboard', () {
    test('UC-A1.1 · first-enrollment CRAM onboard is PQ-native', () {
      // GIVEN @alice unactivated; aliceS = pq; CRAM activation secret in hand;
      //       no keys exist.
      // WHEN  alice1 runs CRAM onboarding.
      // THEN  alice1.APKAM = pq and authenticates via PQ APKAM (no RSA APKAM
      //       needed for auth); public:pq_signing_root@alice exists, is
      //       MUTABLE (what is create-once is _rootlock@alice, the mint lock)
      //       and alice1 holds its private; alice1.KP registered in E1's record but not published
      //       (discoverable only via enroll:listns). Legacy material is STILL
      //       cut and published BY DEFAULT (decisions 37, reversing the old
      //       Decision #1): the RSA encryption keypair + selfEncryptionKey are
      //       minted (the PQ data path never touches them) and
      //       public:publickey@alice is present unless the opt-OUT flag is
      //       set.
      provenIn(
        'tests/at_functional_test/test/pq_native_onboard_live_test.dart',
        'UC-A1.1 · a CRAM activation is PQ-native, and still legacy-reachable',
        proves: 'pqNativeOnboard activates a fresh atSign against a live '
            'atServer and the ML-DSA-65 APKAM then authenticates on a NEW '
            'connection from the keyfile alone — no RSA APKAM exists '
            'anywhere, so the atServer can only have verified an ML-DSA PKAM '
            'signature against the enrollment activation created. The APKAM '
            'is filed as typed material with the flat fields left empty, the '
            'signing root is created and the record the atServer stored for '
            'it does not carry immutable, metadata.keyPackage is on the '
            'enrollment record via '
            'enroll:listns, and the legacy encryption keypair, '
            'selfEncryptionKey and public:publickey are all present by '
            'default.',
      );
    });
  });
}
