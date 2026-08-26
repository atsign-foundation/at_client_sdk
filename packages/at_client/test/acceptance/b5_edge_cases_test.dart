/// B5 · Edge cases.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 12.
library;

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import 'proven_elsewhere.dart';

void main() {
  group('B5 · edge cases', () {
    test('UC-B5.1 · offline enrollment pulls the signing root later', () {
      // GIVEN alice2 was offline during the retrofit wave; pq_signing_root was
      //       created by alice1.
      // WHEN  alice2 next comes online and retrofits.
      // THEN  pq_signing_root has no namespace, so it has NO enroll:listns
      //       push — its requestSecret is the steady-state path, answered by any
      //       online holder and persisting until one answers. Namespaced nskey
      //       privates missed during the offline window arrive by the PUSH
      //       primary path once a holder is online, with requestSecret as the
      //       backstop.
      //
      // The row splits, and both halves are now proven. Namespaced nskey
      // privates arrive by the push path (NskeySeeding's conveyance). The
      // headline half — requestSecret as the steady-state route to the root —
      // had no initiator until PqSigningRoot.requestPrivateIfAbsent, and could
      // not be driven until AtClientImpl's instance cache was keyed by
      // (atSign, enrollmentId): before that every "enrollment" in a test was
      // identical to the approver's client, so the request was a client asking
      // itself over a connection carrying no enrollment id.
      provenIn(
        'tests/at_functional_test/test/signing_root_pull_two_enrollments_test.dart',
        'a holder answers another enrollment and the private is filed',
        proves: 'between two genuinely distinct approved APKAM enrollments, a '
            'seeker holding no root private asks, a holder answers over the '
            'envelope channel, and the private is filed into the seeker\'s '
            'keyfile byte-for-byte — with the seeker asserted to start with '
            'nothing and the two enrollments asserted to differ',
      );
    });

    test('UC-B5.2 · reading legacy history after retrofit', () async {
      // GIVEN alice1 retrofitted; the old legacy enrollment aged out; the legacy
      //       ENCRYPTION key is retained.
      // WHEN  alice1 reads pre-PQ data.
      // THEN  it decrypts via the legacy provider (reads are universal) and
      //       providerId routes per value. PQ retrofit NEVER makes old data
      //       unreadable.
      //
      // The claim that matters here, and the one the cross-cutting
      // "reads are universal" row does NOT make, is that routing is decided
      // **per value** rather than per client or per namespace. After a retrofit
      // a single namespace holds both eras at once — everything written before
      // it and everything written after — so a client that picked one scheme
      // for the namespace would be wrong about half of it.
      const namespace = 'app_1.my_apps';
      final legacy = _RecordingProvider(legacyCryptoProviderId);
      final pq = _RecordingProvider(symmetricAesGcmCryptoProviderId);

      final client = MockAtClient();
      // The retrofitted client: writes the PQ scheme by default, and has NOT
      // dropped the legacy provider — that retention is what "the legacy
      // ENCRYPTION key is retained" means in config terms.
      client.getPreferences().crypto = CryptoConfig(
          defaultProviderId: symmetricAesGcmCryptoProviderId,
          providers: [legacy, pq]);
      final runtime = CryptoRuntime(client);

      AtKey record(String name, String providerId) => AtKey()
        ..key = name
        ..namespace = namespace
        ..sharedBy = '@alice'
        ..metadata =
            (Metadata()..appMetadata = AppMetadata(providerId: providerId));

      // Two records, same atSign, same namespace, different eras.
      expect(
          await runtime.decryptForGet(
              record('written_in_2024', legacyCryptoProviderId), 'old'),
          '$legacyCryptoProviderId decrypted old');
      expect(
          await runtime.decryptForGet(
              record('written_today', symmetricAesGcmCryptoProviderId), 'new'),
          '$symmetricAesGcmCryptoProviderId decrypted new');

      expect(legacy.decryptCalls, 1,
          reason: 'the pre-retrofit record must reach the legacy provider — if '
              'it reached the PQ one, retrofitting made old data unreadable, '
              'which is the single thing this row exists to forbid');
      expect(pq.decryptCalls, 1,
          reason: 'and the post-retrofit record must reach the PQ one, or the '
              'routing is not per-value at all and one of these two passed by '
              'accident');

      // And a NEW write in that same namespace still goes out PQ: retaining
      // the ability to read the old era must not drag the write default back.
      //
      // Asked of `providerIdFor`, which is where the write scheme is actually
      // decided. `encryptForPut` routes by the id already stamped on the key,
      // so asking IT which scheme a new write gets would answer "legacy" for
      // every unstamped key and prove nothing.
      final fresh = AtKey()
        ..key = 'written_next'
        ..namespace = namespace
        ..sharedBy = '@alice'
        ..metadata = Metadata();
      expect(CryptoRuntime.providerIdFor(client, null, atKey: fresh),
          symmetricAesGcmCryptoProviderId,
          reason: 'reads stay universal; writes move forward');
    });

    test('UC-B5.3 · two enrollments race to create the signing root', () {
      // GIVEN alice1 and alice3 both reach the mint step with pq_signing_root
      //       absent.
      // WHEN  both attempt to take the _rootlock@alice mint lock.
      // THEN  exactly one takes it and publishes; the other is refused the
      //       lock and falls through to REQUEST, having generated no keypair
      //       and filed nothing, so there is no orphaned data to discard.
      provenIn(
        'tests/at_functional_test/test/enrollment_chain_link_live_test.dart',
        'the enrollment that loses the race does not mint a second root',
        proves: 'the loser returns null rather than publishing or retrying, '
            'leaves the published record untouched — which is now its own '
            'check rather than the atServer refusing it — and a '
            'namespace-scoped enrollment declines to attempt the mint at all',
      );
    });

    test('UC-B5.4 · two enrollments race to mint a namespace nskey', () {
      // GIVEN alice1 and alice3 both decide namespace n needs an nskey, each
      //       having read the atServer rather than local storage.
      // WHEN  both attempt the _nskeylock.n@alice lock.
      // THEN  one takes it, re-reads under it, and adopts what a sibling
      //       published rather than overwriting it; the loser adopts a
      //       published key or fails loudly, never mints.
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'every advertisement read on the mint path goes to the atServer',
        proves: 'the decision to mint is taken against the atServer, not '
            'against local storage where a sibling publication lags sync — '
            'reading that absence as a cold start is what mints a second key',
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a winner that published while this client took the lock is adopted',
        proves: 'the winner re-reads under the lock and adopts, so a sibling '
            'that published between the first read and the take is not '
            'overwritten',
          clauses: [
            'It **re-reads under the lock**, because a sibling may have '
            'published',
          ]
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a loser with nothing published fails rather than minting',
        proves: 'the loser does not mint and does not wait on another '
            "device's crash — a put fails loudly and the retry is the next "
            'client start',
      );
    });

    test('UC-B5.5 · the mint lock has no release but its ttl', () {
      // GIVEN an enrollment holds the lock and finishes minting.
      // WHEN  it completes.
      // THEN  it does not delete the lock; the ttl is the only release, and a
      //       lock key with no ttl is refused outright.
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'the winner does not release the lock — the ttl does',
        proves: 'no delete means no stolen release, so a holder that overruns '
            "cannot free a successor's lock",
          clauses: [
            'The ttl is the only release, which is what makes the record an',
          ]
      );
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a lock key with no ttl is refused outright',
        proves: 'with nothing deleting the record, a missing ttl would block '
            'minting permanently rather than late',
      );
    });

    test('UC-B5.6 · a rotation inside the cooldown is refused, then succeeds',
        () {
      // GIVEN namespace n was minted or rotated within mintLockTtl.
      // WHEN  the same enrollment asks to rotate n.
      // THEN  refused, naming the cooldown; accepted once the ttl lapses.
      //
      // ⚠️ Cited live and NOT from a unit test on purpose. The interlock is
      // the atServer refusing a second create of an immutable record; a mocked
      // executeVerb accepts the second take, so every unit test of this path
      // is green whether or not the cooldown exists.
      // Cited up to the apostrophe: provenIn matches raw source, and the test
      // is named with an escaped `\'`, so the full name is not the string in
      // the file. The prefix identifies it uniquely.
      provenIn(
        'tests/at_functional_test/test/nskey_rotation_live_test.dart',
        'a rotation inside the mint lock',
        proves: 'the refusal names the cooldown and says the retry waits the '
            'ttl out, and the same call from the same client for the same '
            'namespace is accepted once it lapses — the control without which '
            'the refusal would prove nothing',
      );
    });

    test('UC-B5.7 · a winner that overruns its lease publishes nothing', () {
      // GIVEN alice1 takes the lock at T0 and is still minting at T0+ttl,
      //       while alice3 wins the next election and mints.
      // WHEN  alice1 reaches its publish.
      // THEN  it abandons, turning "two mints" into "one mint, by alice3".
      provenIn(
        'packages/at_client/test/nskey_minting_test.dart',
        'a mint that overruns its lease publishes nothing',
        proves: 'the lease is stamped before the take goes out, so the client '
            'errs early rather than late, and the election window bounding '
            'when the three attempt does not bound how long the winner takes',
      );
    });

    test('UC-B5.8 · a client that configures nothing still takes part', () {
      // GIVEN a client built with no CryptoConfig at all.
      // WHEN  it resolves providers, and when a peer seals data to it.
      // THEN  the era default supplies the providers and it opens what the
      //       peer sealed — configuration selects behaviour, not capability.
      provenIn(
        'tests/at_functional_test/test/crypto_era_default_test.dart',
        'a client that named no CryptoConfig still resolves the nskey providers',
        proves: 'the era default supplies the nskey providers to a client that '
            'named none, so an app that never mentions crypto is not silently '
            'excluded from PQ',
      );
      provenIn(
        'tests/at_end2end_test/test/pq/era_default_read_test.dart',
        'bob, given no CryptoConfig at all, opens what alice sealed to him',
        proves: 'the other half, and the one that makes it a product claim '
            'rather than a resolver detail — cross-atSign, on the wire, with '
            'the receiving side configured with nothing',
          clauses: [
            'the era default supplies the nskey providers, and the client '
            'opens what the peer sealed',
          ]
      );
    });

    test('UC-B5.9 · a conveyed private is filed only if addressed here', () {
      // GIVEN privates are conveyed and swept off the atServer.
      // WHEN  the sweep meets one addressed to a different key package.
      // THEN  it is not filed. Arrival is not entitlement.
      provenIn(
        'tests/at_functional_test/test/conveyed_key_collection_test.dart',
        'a conveyed private is swept off the atServer and filed into the keyfile',
        proves: 'the positive control without which the refusal below could '
            'pass by the sweep simply not working',
      );
      provenIn(
        'tests/at_functional_test/test/conveyed_key_collection_test.dart',
        'a private addressed to another key package is not filed',
        proves: 'the channel is a shared surface, so "it arrived" can never be '
            'the test for "it is mine" — this is what stops one enrollment '
            "collecting another's material by being first to look",
          clauses: [
            'Sweeping is not the same as accepting: the channel is a shared '
            'surface',
          ]
      );
    });

    test('UC-B5.10 · an unentitled enrollment does not ask for the root', () {
      // GIVEN an enrollment whose grants do not entitle it to the signing root.
      // WHEN  it reaches the point an entitled one would request it.
      // THEN  it does not ask — the check is on the seeker, before the request.
      provenIn(
        'tests/at_functional_test/test/signing_root_pull_test.dart',
        'an enrollment not entitled to the root does not ask for it',
        proves: 'the refusal half of UC-B5.1. A pull path that asks '
            "unconditionally leaves the holder's answer as the only thing "
            'standing between an enrollment and material it may not hold',
          clauses: [
            'The check is on the seeker, before the request, not only on the '
            'holder',
          ]
      );
    });

    test('UC-B5.11 · an enrollment that missed the mint heals from a holder',
        () {
      // GIVEN a namespace was minted while this enrollment was absent.
      // WHEN  it next starts.
      // THEN  it requests the private from a holder rather than minting a
      //       rival generation.
      provenIn(
        'tests/at_functional_test/test/nskey_self_heal_live_test.dart',
        'an enrollment that missed the mint pulls the private from a holder',
        proves: 'this is what makes an absent or losing enrollment inert '
            'rather than divergent, and why the nskey path needs no retire: a '
            'generation nobody advertises is never selected, because selection '
            'is by the kid in the envelope being opened',
          clauses: [
            'it **requests the private from a holder** and files it, rather '
            'than minting a rival generation',
          ]
      );
    });

    test('UC-B5.12 · the owner verifies her own advertisement as a peer would',
        () {
      // GIVEN alice published an nskey advertisement.
      // WHEN  alice herself resolves and verifies it.
      // THEN  she takes the same path a peer takes; an unminted namespace
      //       resolves to nothing rather than to an error or a guess.
      provenIn(
        'tests/at_functional_test/test/nskey_published_ring_test.dart',
        'the owner verifies her own advertisement the same way a peer would',
        proves: 'one verify path means a defect in verification cannot hide '
            'behind the common case — it is what makes "same-atSign and '
            'cross-atSign are the same code" tested rather than aspirational',
          clauses: [
            'she takes the **same verify path a peer takes**',
          ]
      );
      provenIn(
        'tests/at_functional_test/test/nskey_published_ring_test.dart',
        'a namespace nobody minted for resolves to nothing',
        proves: 'the absent case resolves to nothing rather than to an error '
            'or a guess, which is what lets a caller distinguish "not minted" '
            'from "minted and unreadable"',
      );
    });
  });
}

/// Names itself in its output, so a routing assertion cannot pass by reaching
/// the wrong provider and getting a plausible-looking string back.
///
/// Extends rather than implements: a member added to [CryptoProvider] with a
/// body reaches a subclass, while an implementer silently loses it and fails
/// at runtime with nothing the analyzer can say.
class _RecordingProvider extends CryptoProvider {
  @override
  final String id;

  int decryptCalls = 0;

  _RecordingProvider(this.id);

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String plaintext) async =>
      '$id encrypted $plaintext';

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    decryptCalls++;
    return '$id decrypted $ciphertext';
  }
}
