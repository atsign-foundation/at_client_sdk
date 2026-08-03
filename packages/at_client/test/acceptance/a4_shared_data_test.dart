/// A4 · E2EE across atSigns (shared data) + cross-atSign notification.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 5.
library;

import 'package:test/test.dart';

import 'blockers.dart';

void main() {
  group('A4 · shared data', () {
    test('UC-A4.1 · alice to bob, both PQ-native, bob has the namespace key',
        () {
      // GIVEN @alice, @bob pq-native; @bob published
      //       public:__nskey.app_1.my_apps@bob when he first used the namespace;
      //       bob1, bob2 hold its private; @bob readiness = ready.
      // WHEN  alice1 does put @bob:<k>.app_1.my_apps@alice (shouldEncrypt).
      // THEN  bob's clients decapsulate bob's CK record with bob's nskey private
      //       and read; alice's clients decapsulate the self-copy's CK — a
      //       SECOND CK in her own scope, since CKs are per recipient — with
      //       alice's nskey private. PQ end to end — no RSA on any path. An
      //       unauthorised @bob enrollment can neither fetch the ciphertext
      //       (server-gated) nor decrypt it.
      fail('not implemented');
    }, skip: b1CrossAtSign);

    test('UC-A4.2 · alice to bob where bob has no namespace key, share fails',
        () {
      // GIVEN @alice, @bob pq-native; @bob has public:pq_signing_root@bob but
      //       NO public:__nskey.app_1.my_apps@bob — he has never used or
      //       authorised that namespace.
      // WHEN  alice1 shares @bob:<k>.app_1.my_apps@alice.
      // THEN  the share FAILS, with an exception naming @bob and the namespace
      //       so the app can say the recipient has not enabled it rather than
      //       report an encryption error. Bob's signing root is not a KEM
      //       target and cannot stand in. A pre-flight capability query answers
      //       the same question before the user composes anything. With the
      //       legacy fallback opted in (final 3.x only) the share proceeds
      //       under legacy — the invitation path, which ends at 4.x. Once bob
      //       uses or authorises the namespace his nskey is published and
      //       alice's next ensureCurrent picks it up by plookup.
      fail('not implemented');
    }, skip: b1CrossAtSign);

    test('UC-A4.3 · multi-enrollment both ends', () {
      // GIVEN alice (aE1, aE2) and bob (bE1, bE2) all PQ; bob has
      //       public:__nskey.app_1.my_apps@bob.
      // WHEN  alice2 shares with @bob.
      // THEN  all of bob's authorised enrollments read; all of alice's
      //       authorised enrollments read the self-copy; no authorised
      //       enrollment is left unable to decrypt.
      fail('not implemented');
    }, skip: b1CrossAtSign);

    test('UC-A4.4 · cross-atSign notification carrying an encrypted value', () {
      // GIVEN @alice, @bob pq-native; @bob published his nskey for the
      //       namespace; @bob readiness ready; bob1 on a monitor.
      // WHEN  alice1 notifies @bob with an encrypted value.
      // THEN  the value decrypts on every authorised bob enrollment with the
      //       same routing as a shared put; negotiation gates the notification
      //       scheme on BOB's readiness; offline-then-online bob still decrypts
      //       the queued notification; appMetadata is present on the frame;
      //       signal-only notifications are unaffected.
      fail('not implemented');
    }, skip: b1CrossAtSign);
  });
}
